// ergou-ime — SenseVoice Small via sherpa-onnx (offline recognizer).
// SPDX-License-Identifier: GPL-3.0-only
//
// Compiled only with ERGOU_WITH_SHERPA (scripts/configure.sh). Integration
// seam for M2 (T2.1) in docs/PLAN-v1.md; not yet run on a Mac.
//
// Model files are NOT in the repository and NOT bundled. ErgouIME Settings
// downloads them after a confirmation dialog (M3); during development
// scripts/fetch-sensevoice-model.sh does it. Location: App Group container,
// Models/sense-voice/ (model.int8.onnx + tokens.txt) — see Shared/Paths.swift.

#if ERGOU_WITH_SHERPA
import Foundation

final class SenseVoiceTranscriber: SpeechTranscriber {
    private let recognizer: OpaquePointer

    init?(modelDirectory: URL) {
        let model = modelDirectory.appendingPathComponent("model.int8.onnx").path
        let tokens = modelDirectory.appendingPathComponent("tokens.txt").path
        guard FileManager.default.fileExists(atPath: model),
              FileManager.default.fileExists(atPath: tokens) else {
            Log.speech.error("SenseVoice model missing; run scripts/fetch-sensevoice-model.sh")
            return nil
        }

        // C strings only need to live until SherpaOnnxCreateOfflineRecognizer returns.
        var owned: [UnsafeMutablePointer<CChar>] = []
        func c(_ s: String) -> UnsafePointer<CChar>? {
            let p = strdup(s)!
            owned.append(p)
            return UnsafePointer(p)
        }
        defer { owned.forEach { free($0) } }

        var config = SherpaOnnxOfflineRecognizerConfig()
        config.feat_config.sample_rate = 16000
        config.feat_config.feature_dim = 80
        config.model_config.sense_voice.model = c(model)
        config.model_config.sense_voice.language = c("auto") // zh / en / yue / ja / ko
        config.model_config.sense_voice.use_itn = 1          // "一百二十" → "120", punctuation
        config.model_config.tokens = c(tokens)
        config.model_config.num_threads = 2
        config.model_config.provider = c("cpu")
        config.model_config.debug = 0
        config.decoding_method = c("greedy_search")

        guard let r = SherpaOnnxCreateOfflineRecognizer(&config) else {
            Log.speech.error("SherpaOnnxCreateOfflineRecognizer failed")
            return nil
        }
        recognizer = r
    }

    deinit {
        SherpaOnnxDestroyOfflineRecognizer(recognizer)
    }

    func transcribe(samples: [Float], sampleRate: Int) -> String? {
        guard !samples.isEmpty, let stream = SherpaOnnxCreateOfflineStream(recognizer) else { return nil }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
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
