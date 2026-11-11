// ergou-ime — final results with the accurate recogniser (Qwen3-ASR).
// SPDX-License-Identifier: GPL-3.0-only
//
// VoiceSession cuts a recording into segments at pauses. SenseVoice (fast)
// recognises them for the live text; when Qwen3-ASR is installed, each
// finished segment is also queued here and its result replaces SenseVoice's
// in what gets typed. Without Qwen3-ASR (or if it fails to load) the
// SenseVoice text is used, as before.
//
// Own serial queue, so loading the ~1 GB model and decoding never hold up
// the live preview or the main thread:
//   - begin() at the start of a recording loads the model in the background
//     (first load ~0.9 s, plus a one-off SHA-256 check of the files);
//   - segments are decoded while the user is still speaking;
//   - 10 idle minutes after the last recording the model is released
//     (1.5–2.2 GB while loaded, D's Mac 2026-11-10).
// Logs timings only, never text (Privacy rule 4).

#if ERGOU_WITH_SHERPA
import Foundation

final class FinalPass {
    static let shared = FinalPass()
    static let idleRelease: TimeInterval = 10 * 60

    private let queue = DispatchQueue(label: "com.codamon.inputmethod.Ergou.speech.final", qos: .userInitiated)

    // All on `queue`.
    private var engine: Qwen3Transcriber?
    private var lastFailure: Date?
    private var recording = -1
    private var results: [Int: String] = [:]
    private var decodeMs = 0.0
    private var idleTimer: DispatchSourceTimer?
    /// This recording's hotwords, also for a model that loads only at submit().
    private var hotwords = ""

    /// Cheap check (files exist), main thread.
    static var isInstalled: Bool { SpeechModelFiles.qwen3ASR06BInt8.isPresent }

    /// Start of a recording. `id` tells this recording's segments apart from
    /// a cancelled one's; `hotwords` is TermStore.hotwords. Returns false
    /// when Qwen3-ASR is not installed (SenseVoice gives the final text).
    func begin(recording id: Int, hotwords: String) -> Bool {
        guard Self.isInstalled else { return false }
        queue.async { [self] in
            idleTimer?.cancel()
            idleTimer = nil
            recording = id
            results = [:]
            decodeMs = 0
            self.hotwords = hotwords
            loadIfNeeded()
            engine?.hotwords = hotwords
        }
        return true
    }

    /// A finished segment (already gain-normalised), index in recording order.
    /// `decoded` runs on this pass's queue once the segment is done, with its
    /// text (nil: nothing recognised, or Qwen3-ASR not loaded) — for the
    /// cloud tidy-up, which sends each segment as soon as it is final.
    /// Not called for a cancelled recording.
    func submit(recording id: Int, index: Int, samples: [Float], sampleRate: Int,
                decoded: ((String?) -> Void)? = nil) {
        queue.async { [self] in
            guard id == recording else { return }            // cancelled recording
            loadIfNeeded()
            guard let engine else { decoded?(nil); return }
            let started = DispatchTime.now()
            if let text = engine.transcribe(samples: samples, sampleRate: sampleRate) { results[index] = text }
            decodeMs += Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e6
            decoded?(results[index])
        }
    }

    enum Outcome {
        /// One entry per segment (nil = nothing recognised).
        case texts([String?])
        /// Qwen3-ASR did not load: the caller falls back to SenseVoice.
        case unavailable
        /// The recording was cancelled meanwhile.
        case cancelled
    }

    /// After the last submit: calls `done` on this pass's queue.
    func finish(recording id: Int, segments: Int, done: @escaping (Outcome) -> Void) {
        queue.async { [self] in
            guard id == recording else { done(.cancelled); scheduleRelease(); return }
            guard engine != nil else { done(.unavailable); scheduleRelease(); return }
            let out = (0..<segments).map { results[$0] }
            let terms = engine?.hotwords.isEmpty == false ? engine!.hotwords.split(separator: ",").count : 0
            Log.speech.notice("Qwen3-ASR decoded \(segments, privacy: .public) segments in \(self.decodeMs, format: .fixed(precision: 0), privacy: .public) ms, \(terms, privacy: .public) terms")
            results = [:]
            done(.texts(out))
            scheduleRelease()
        }
    }

    /// Recording cancelled: drop its queued segments.
    func cancel(recording id: Int) {
        queue.async { [self] in
            guard id == recording else { return }
            recording = -1
            results = [:]
            scheduleRelease()
        }
    }

    // MARK: - Loading and releasing (on `queue`)

    private func loadIfNeeded() {
        guard engine == nil else { return }
        // A file that failed its check is not hashed again on every recording.
        if let last = lastFailure, Date().timeIntervalSince(last) < 60 { return }
        let files = SpeechModelFiles.qwen3ASR06BInt8
        let started = DispatchTime.now()
        // Settings (network access) wrote these files: clone them into our
        // private container, check the clones against hashes fixed in our
        // code, and let onnxruntime parse only those (rule 9).
        guard let directory = files.verifiedPrivateCopy() else {
            Log.speech.error("Qwen3-ASR model failed its SHA-256 check")
            lastFailure = Date()
            return
        }
        let checked = DispatchTime.now()
        engine = Qwen3Transcriber(modelDirectory: directory)
        let checkMs = Double(checked.uptimeNanoseconds - started.uptimeNanoseconds) / 1e6
        let loadMs = Double(DispatchTime.now().uptimeNanoseconds - checked.uptimeNanoseconds) / 1e6
        if engine == nil {
            lastFailure = Date()
            Log.speech.error("Qwen3-ASR failed to load")
        } else {
            lastFailure = nil
            engine?.hotwords = hotwords
            Log.speech.notice("Qwen3-ASR loaded in \(loadMs, format: .fixed(precision: 0), privacy: .public) ms (file check \(checkMs, format: .fixed(precision: 0), privacy: .public) ms)")
        }
    }

    private func scheduleRelease() {
        idleTimer?.cancel()
        guard engine != nil else { idleTimer = nil; return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.idleRelease)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.engine = nil
            self.idleTimer = nil
            Log.speech.notice("Qwen3-ASR released after \(Int(Self.idleRelease / 60), privacy: .public) idle minutes")
        }
        timer.resume()
        idleTimer = timer
    }
}
#endif
