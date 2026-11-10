// ergou-ime — talks to ErgouIME Corrector (XPC) for voice correction.
// SPDX-License-Identifier: GPL-3.0-only
//
// The input method itself never runs a language model: the service does,
// in its own process, and exits when idle. Every call has a deadline; on
// timeout or error the uncorrected text is used.

import Foundation

final class CorrectorClient {
    static let shared = CorrectorClient()

    private var connection: NSXPCConnection?
    /// True once the service reported the model loaded (prepare); the first
    /// call after a cold start gets a longer deadline.
    private(set) var isWarm = false

    private func proxy(onError: @escaping () -> Void) -> CorrectorXPC? {
        if connection == nil {
            let c = NSXPCConnection(serviceName: CorrectorService.name)
            c.remoteObjectInterface = NSXPCInterface(with: CorrectorXPC.self)
            c.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.connection = nil; self?.isWarm = false } }
            c.interruptionHandler = { [weak self] in DispatchQueue.main.async { self?.connection = nil; self?.isWarm = false } }
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in onError() } as? CorrectorXPC
    }

    /// The engine and model chosen in Settings, or nil when correction is off
    /// or cloud (CloudCorrector, a different XPC service).
    static var current: (engine: VoiceCorrection, model: LocalCorrectionModel)? {
        let engine = SharedSettings.voiceCorrection
        switch engine {
        case .apple, .local: return (engine, SharedSettings.localCorrectionModel)
        case .cloud, .off: return nil
        }
    }

    /// Warm up while the user speaks.
    func prepare() {
        guard let (engine, model) = Self.current else { return }
        proxy(onError: {})?.prepare(engine: engine.rawValue, model: model.rawValue) { [weak self] ok in
            DispatchQueue.main.async { self?.isWarm = ok }
        }
    }

    /// Tidy long text in chunks of whole sentences (the local model has a
    /// 2048-token context), one after another. Each chunk's deadline grows
    /// with its length; a cold first chunk gets 15 s for loading the model.
    /// A chunk that fails or times out is kept as it was.
    func tidy(_ text: String, done: @escaping (_ result: String, _ changed: Bool) -> Void) {
        let chunks = Self.chunks(text, limit: 300)
        var out: [String] = []
        var changed = false
        func step(_ i: Int) {
            guard i < chunks.count else { done(out.joined(), changed); return }
            let chunk = chunks[i]
            var timeout = max(3, Double(chunk.count) * 0.012 + 1.5)
            if i == 0, !isWarm { timeout = max(timeout, 15) }
            correct(chunk, timeout: timeout) { result in
                if let result { out.append(result); changed = true } else { out.append(chunk) }
                step(i + 1)
            }
        }
        step(0)
    }

    /// Split after 。！？!? (or newlines) into chunks of at most ~`limit` chars.
    static func chunks(_ text: String, limit: Int) -> [String] {
        var sentences: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if "。！？!?\n".contains(ch) { sentences.append(current); current = "" }
        }
        if !current.isEmpty { sentences.append(current) }
        var chunks: [String] = []
        var buf = ""
        for s in sentences {
            if !buf.isEmpty, buf.count + s.count > limit { chunks.append(buf); buf = "" }
            buf += s
        }
        if !buf.isEmpty { chunks.append(buf) }
        return chunks
    }

    /// Calls `done` on the main queue exactly once, with the corrected text
    /// or nil.
    func correct(_ text: String, timeout: TimeInterval = 3, done: @escaping (String?) -> Void) {
        guard let (engine, model) = Self.current else { done(nil); return }
        let lock = NSLock()
        var finished = false
        let finish: (String?) -> Void = { value in
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            DispatchQueue.main.async {
                if value != nil { self.isWarm = true }
                done(value)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout + 0.3) { finish(nil) }
        guard let remote = proxy(onError: { finish(nil) }) else { finish(nil); return }
        remote.correct(text, engine: engine.rawValue, model: model.rawValue, timeout: timeout) { finish($0) }
    }
}
