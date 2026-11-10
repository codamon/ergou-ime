// ergou-ime — Qwen3-ASR 0.6B via sherpa-onnx (offline recognizer).
// SPDX-License-Identifier: GPL-3.0-only
//
// The accurate recogniser for final results (D's voice, 2026-11-10: 2.9 %
// character errors vs SenseVoice 3.9 %, 0.3 % with hotwords; see
// docs/PLAN-v1.md M2.6). About 6× slower than SenseVoice, so the live
// preview stays on SenseVoice and this one only runs on finished segments
// (FinalPass.swift).
//
// Output already has punctuation; numbers come out as Chinese words
// ("二点零点一"), which 自动整理 turns into digits. Do not run the
// CT-Transformer punctuator on it (double punctuation).
//
// Hotwords are a per-stream option (sherpa-onnx v2.0.1
// offline-recognizer-qwen3-asr-impl.cc reads stream option "hotwords"
// before the recognizer's config), so a changed word list never needs the
// ~1 GB model to be loaded again.
//
// Model files are downloaded by ErgouIME Settings into the App Group
// container (Models/qwen3-asr/) and checked against SpeechModelFiles before
// this class sees them.

#if ERGOU_WITH_SHERPA
import Foundation

final class Qwen3Transcriber: SpeechTranscriber {
    private let recognizer: OpaquePointer

    /// Comma-separated terms (VoiceTerms.hotwordString). Set on the queue
    /// that calls `transcribe`.
    var hotwords = ""

    init?(modelDirectory: URL, threads: Int32 = 4) {
        let path = { (name: String) in modelDirectory.appendingPathComponent(name).path }
        let required = ["conv_frontend.onnx", "encoder.int8.onnx", "decoder.int8.onnx", "tokenizer/vocab.json"]
        guard required.allSatisfy({ FileManager.default.fileExists(atPath: path($0)) }) else {
            Log.speech.error("Qwen3-ASR model files missing")
            return nil
        }

        var owned: [UnsafeMutablePointer<CChar>] = []
        func c(_ s: String) -> UnsafePointer<CChar>? {
            let p = strdup(s)!
            owned.append(p)
            return UnsafePointer(p)
        }
        defer { owned.forEach { free($0) } }

        var config = SherpaOnnxOfflineRecognizerConfig()
        config.feat_config.sample_rate = 16000
        config.feat_config.feature_dim = 128              // Whisper-style log-mel
        config.model_config.qwen3_asr.conv_frontend = c(path("conv_frontend.onnx"))
        config.model_config.qwen3_asr.encoder = c(path("encoder.int8.onnx"))
        config.model_config.qwen3_asr.decoder = c(path("decoder.int8.onnx"))
        config.model_config.qwen3_asr.tokenizer = c(modelDirectory.appendingPathComponent("tokenizer", isDirectory: true).path)
        // The KV cache holds prompt + hotwords + audio + output. sherpa-onnx's
        // default 512 is too small for a 25 s segment (328 audio tokens) with
        // 200 hotword tokens: it silently drops the end of the audio. 768
        // fits; the cache is ~180 MB while a segment decodes, then freed.
        config.model_config.qwen3_asr.max_total_len = Self.maxTotalLength
        config.model_config.qwen3_asr.max_new_tokens = Self.maxNewTokens
        // Other fields 0 = sherpa-onnx defaults (near-greedy sampling).
        config.model_config.num_threads = threads
        config.model_config.provider = c("cpu")
        config.model_config.debug = 0
        config.decoding_method = c("greedy_search")

        guard let r = SherpaOnnxCreateOfflineRecognizer(&config) else {
            Log.speech.error("SherpaOnnxCreateOfflineRecognizer (Qwen3-ASR) failed")
            return nil
        }
        recognizer = r
    }

    static let maxTotalLength: Int32 = 768
    /// 25 s of fast speech is ~150 characters; leave room.
    static let maxNewTokens: Int32 = 200

    deinit {
        SherpaOnnxDestroyOfflineRecognizer(recognizer)
    }

    /// With hotwords, near-silent audio can make the model recite the
    /// hotword list instead (1.1 s of breath with 107 terms, D's Mac
    /// 2026-11-10). Such output is thrown away and the segment decoded
    /// again without hotwords.
    func transcribe(samples: [Float], sampleRate: Int) -> String? {
        let seconds = Double(samples.count) / Double(max(sampleRate, 1))
        if !hotwords.isEmpty, let text = decode(samples, sampleRate, hotwords: hotwords) {
            if !Self.isImplausible(text, seconds: seconds, hotwords: hotwords) { return text }
            Log.speech.notice("Qwen3-ASR output looked like the hotword list; decoding again without")
        }
        guard let text = decode(samples, sampleRate, hotwords: "") else { return nil }
        return Self.isImplausible(text, seconds: seconds, hotwords: "") ? nil : text
    }

    /// Far more characters than anyone says in that time, a bare
    /// "language" (prompt residue when the audio did not fit), or mostly
    /// hotwords strung together.
    static func isImplausible(_ text: String, seconds: Double, hotwords: String) -> Bool {
        let core = text.filter { !$0.isWhitespace && !$0.isPunctuation }
        if core.lowercased() == "language" { return true }
        if Double(core.count) > 12 + 10 * seconds { return true }
        let terms = hotwords.split(separator: ",").map { $0.filter { !$0.isWhitespace }.lowercased() }
            .filter { !$0.isEmpty }
        guard terms.count >= 3 else { return false }
        var rest = core.lowercased()
        var hits = 0
        for t in terms.sorted(by: { $0.count > $1.count }) where rest.contains(t) {
            hits += 1
            rest = rest.replacingOccurrences(of: t, with: "")
        }
        return hits >= 4 && rest.count * 2 < core.count
    }

    private func decode(_ samples: [Float], _ sampleRate: Int, hotwords: String) -> String? {
        guard !samples.isEmpty, let stream = SherpaOnnxCreateOfflineStream(recognizer) else { return nil }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        if !hotwords.isEmpty {
            SherpaOnnxOfflineStreamSetOption(stream, "hotwords", hotwords)
        }
        // Output budget by duration (~8 tokens/s is well above fast speech):
        // a runaway decode (hotword recital, repetition) stops early.
        let seconds = Double(samples.count) / Double(max(sampleRate, 1))
        let budget = min(Int(Self.maxNewTokens), 16 + Int(8 * seconds))
        SherpaOnnxOfflineStreamSetOption(stream, "max_new_tokens", String(budget))
        samples.withUnsafeBufferPointer { buf in
            SherpaOnnxAcceptWaveformOffline(stream, Int32(sampleRate), buf.baseAddress, Int32(buf.count))
        }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { return nil }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        guard let text = result.pointee.text else { return nil }
        let s = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
#endif
