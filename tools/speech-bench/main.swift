// ergou-ime — run the input method's own recogniser code on WAV files,
// and check the voice-term rules. See README.md.
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func readWave(_ path: String) -> (samples: [Float], rate: Int)? {
    guard let wave = SherpaOnnxReadWave(path) else { return nil }
    defer { SherpaOnnxFreeWave(wave) }
    let n = Int(wave.pointee.num_samples)
    let samples = Array(UnsafeBufferPointer(start: wave.pointee.samples, count: n))
    return (samples, Int(wave.pointee.sample_rate))
}

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

/// asr <qwen3|sensevoice> <model dir> <hotwords: "" | a,b,c | @file> <out.txt> <wav>...
/// Writes the joined text to out.txt (score2.py extra argument) and one
/// line per file (seconds of audio, ms, text) to stdout.
func runASR(_ args: [String]) {
    guard args.count >= 5 else { fail("usage: asr <qwen3|sensevoice> <model dir> <hotwords> <out.txt> <wav>...") }
    let engine = args[0], dir = URL(fileURLWithPath: args[1]), out = args[3], wavs = Array(args[4...])
    var hot = args[2]
    if hot.hasPrefix("@") {
        guard let file = try? String(contentsOfFile: String(hot.dropFirst()), encoding: .utf8) else { fail("cannot read \(hot)") }
        hot = file.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let t0 = now()
    let transcriber: SpeechTranscriber
    switch engine {
    case "qwen3":
        guard let q = Qwen3Transcriber(modelDirectory: dir) else { fail("Qwen3 load failed") }
        q.hotwords = hot
        transcriber = q
    case "sensevoice":
        guard let s = SenseVoiceTranscriber(modelDirectory: dir) else { fail("SenseVoice load failed") }
        transcriber = s
    default: fail("unknown engine \(engine)")
    }
    print(String(format: "load %.0f ms, %d hotword terms", (now() - t0) * 1000,
                 hot.isEmpty ? 0 : hot.split(separator: ",").count))
    var texts: [String] = []
    var audio = 0.0, spent = 0.0
    for w in wavs {
        guard let (samples, rate) = readWave(w) else { fail("cannot read \(w)") }
        let t = now()
        let text = transcriber.transcribe(samples: samples, sampleRate: rate) ?? ""
        let ms = (now() - t) * 1000
        let seconds = Double(samples.count) / Double(rate)
        audio += seconds; spent += ms / 1000
        texts.append(text)
        print(String(format: "%@\t%.1f s\t%.0f ms\t%@", (w as NSString).lastPathComponent, seconds, ms, text))
    }
    print(String(format: "total %.1f s audio in %.2f s, RTF %.3f", audio, spent, spent / max(audio, 0.001)))
    try? texts.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
}

/// session <qwen3|sensevoice> <model dir> <hotwords> <out.txt> <one long wav>
/// Cuts the recording like VoiceSession does at stop (SpeechSegmenter with
/// the recording's own silence threshold, silent segments skipped, quiet
/// input gain-normalised), then recognises each segment.
func runSession(_ args: [String]) {
    guard args.count == 5, let (all, rate) = readWave(args[4]), rate == SpeechSegmenter.sampleRate else {
        fail("usage: session <engine> <model dir> <hotwords> <out.txt> <16 kHz wav>")
    }
    let silence = SpeechSegmenter.silenceThreshold(all)
    var cuts: [Range<Int>] = []
    var offset = 0
    while let cut = SpeechSegmenter.nextCut(in: all, from: offset, final: false, silence: silence) {
        cuts.append(offset..<cut); offset = cut
    }
    if all.count - offset > rate * 3 / 10 { cuts.append(offset..<all.count) }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speech-bench-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    var paths: [String] = []
    var skipped = 0
    for (i, r) in cuts.enumerated() {
        let seg = Array(all[r])
        guard SpeechSegmenter.voicedSeconds(seg, silence: silence) >= 0.3 else { skipped += 1; continue }
        let peak = seg.reduce(Float(0)) { max($0, abs($1)) }
        let gain: Float = peak > 0 && peak < 0.25 ? min(20, 0.5 / peak) : 1
        let path = dir.appendingPathComponent(String(format: "cut%02d.wav", i + 1)).path
        let scaled = seg.map { $0 * gain }
        let ok = scaled.withUnsafeBufferPointer { SherpaOnnxWriteWave($0.baseAddress, Int32($0.count), Int32(rate), path) }
        guard ok != 0 else { fail("cannot write \(path)") }
        paths.append(path)
    }
    print(String(format: "silence %.0f dB, %d segments (%d silent skipped)", silence, cuts.count, skipped))
    runASR(Array(args[0..<4]) + paths)
}

/// finalpass <hotwords> <wav>...  — FinalPass as the input method drives it
/// (model from Paths.models/qwen3-asr, i.e. ~/Library/Application Support/
/// ErgouIME/Models outside the sandbox): begin, submit every file as a
/// segment, finish; then a cancelled recording. Prints timings.
func runFinalPass(_ args: [String]) {
    guard args.count >= 2 else { fail("usage: finalpass <hotwords> <wav>...") }
    let segments: [(samples: [Float], rate: Int)] = args[1...].map { path in
        guard let wave = readWave(path) else { fail("cannot read \(path)") }
        return wave
    }
    let pass = FinalPass.shared
    let t0 = now()
    guard pass.begin(recording: 1, hotwords: args[0]) else { fail("Qwen3-ASR not installed at \(SpeechModelFiles.qwen3ASR06BInt8.directory.path)") }
    print(String(format: "begin returned after %.1f ms (loading in the background)", (now() - t0) * 1000))
    for (i, s) in segments.enumerated() { pass.submit(recording: 1, index: i, samples: s.samples, sampleRate: s.rate) }
    let done = DispatchSemaphore(value: 0)
    pass.finish(recording: 1, segments: segments.count) { outcome in
        switch outcome {
        case .texts(let t): print(String(format: "finished after %.0f ms, %d/%d segments with text", (now() - t0) * 1000, t.compactMap { $0 }.count, t.count))
            for (i, x) in t.enumerated() { print("  \(i): \(x ?? "(nil)")") }
        case .unavailable: print("unavailable")
        case .cancelled: print("cancelled")
        }
        done.signal()
    }
    done.wait()
    // Second recording, cancelled after one segment: its finish must say so.
    let t1 = now()
    _ = pass.begin(recording: 2, hotwords: args[0])
    pass.submit(recording: 2, index: 0, samples: segments[0].samples, sampleRate: segments[0].rate)
    pass.cancel(recording: 2)
    pass.finish(recording: 2, segments: 1) { outcome in
        if case .cancelled = outcome { print(String(format: "cancelled recording reported as cancelled (%.0f ms, model already loaded)", (now() - t1) * 1000)) }
        else { print("FAIL: cancelled recording not reported as cancelled") }
        done.signal()
    }
    done.wait()
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "asr": runASR(Array(args.dropFirst()))
case "session": runSession(Array(args.dropFirst()))
case "finalpass": runFinalPass(Array(args.dropFirst()))
case "terms": runTermTests()
default: fail("usage: speech-bench asr … | session … | terms")
}
