// ErgouIME Corrector — runs the chosen correction engine.
// SPDX-License-Identifier: GPL-3.0-only
//
// Text in, text out. Never logs text. Exits after 10 idle minutes so a
// loaded model (up to ~5 GB) does not stay in memory.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

final class Corrector: NSObject, CorrectorXPC {
    static let shared = Corrector()

    private let queue = DispatchQueue(label: "com.codamon.inputmethod.Ergou.Corrector", qos: .userInitiated)
    #if ERGOU_WITH_LLAMA
    private var llama: LlamaCorrector?
    private var llamaModel: LocalCorrectionModel?
    private var failedModels = Set<LocalCorrectionModel>()
    #endif
    private var idleTimer: DispatchSourceTimer?
    private static let idleExit: TimeInterval = 10 * 60

    func prepare(engine: String, model: String, reply: @escaping (Bool) -> Void) {
        touch()
        queue.async {
            switch Self.effective(engine) {
            case .local?:
                #if ERGOU_WITH_LLAMA
                reply(self.loadLlama(LocalCorrectionModel(rawValue: model) ?? .recommended) != nil)
                #else
                reply(false)
                #endif
            case .apple?:
                reply(Self.appleAvailable)
            default:
                reply(false)
            }
        }
    }

    /// Apple's model is unavailable on many Macs (e.g. Siri set to 中文（中国
    /// 大陆）hides Apple Intelligence — D's Mac, 2026-11-09). Then use the
    /// local model if one is installed rather than doing nothing.
    private static func effective(_ engine: String) -> VoiceCorrection? {
        let chosen = VoiceCorrection(rawValue: engine)
        if chosen == .apple, !appleAvailable, SharedSettings.localCorrectionModel.files.isPresent {
            return .local
        }
        return chosen
    }

    func correct(_ text: String, engine: String, model: String, timeout: Double,
                 reply: @escaping (String?) -> Void) {
        touch()
        switch Self.effective(engine) {
        case .local?:
            queue.async {
                #if ERGOU_WITH_LLAMA
                let started = Date()
                guard let llama = self.loadLlama(LocalCorrectionModel(rawValue: model) ?? .recommended) else {
                    reply(nil); return
                }
                let left = timeout - Date().timeIntervalSince(started)
                reply(left > 0.2 ? llama.correct(text, timeout: left) : nil)
                #else
                reply(nil)
                #endif
            }
        case .apple?:
            Self.appleCorrect(text, timeout: timeout, reply: reply)
        default:
            reply(nil)
        }
    }

    // MARK: - Local (llama.cpp)

    #if ERGOU_WITH_LLAMA
    /// On `queue`. Checks SHA-256 before loading (Privacy rule 9).
    private func loadLlama(_ model: LocalCorrectionModel) -> LlamaCorrector? {
        if llamaModel == model, let llama { return llama }
        guard !failedModels.contains(model) else { return nil }
        llama = nil
        llamaModel = nil
        let files = model.files
        guard files.isPresent, files.isIntact,
              let loaded = LlamaCorrector(modelPath: files.url(model.fileName).path) else {
            failedModels.insert(model)
            NSLog("ErgouIMECorrector: local model unavailable or failed its check")
            return nil
        }
        llama = loaded
        llamaModel = model
        return loaded
    }
    #endif

    // MARK: - Apple on-device model

    static var appleAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    private static func appleCorrect(_ text: String, timeout: Double, reply: @escaping (String?) -> Void) {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), appleAvailable {
            let once = ReplyOnce(reply)
            let task = Task {
                let session = LanguageModelSession(instructions: CorrectionPrompt.system)
                let response = try? await session.respond(to: text, options: GenerationOptions(temperature: 0))
                once.send(response.flatMap { CorrectionPrompt.accept($0.content, for: text) })
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                task.cancel()
                once.send(nil)
            }
            return
        }
        #endif
        reply(nil)
    }

    // MARK: - Idle exit

    private func touch() {
        DispatchQueue.main.async {
            self.idleTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + Self.idleExit)
            timer.setEventHandler { exit(0) }
            timer.resume()
            self.idleTimer = timer
        }
    }
}

/// Calls the XPC reply exactly once (model result or timeout, whichever is first).
private final class ReplyOnce: @unchecked Sendable {
    private var reply: ((String?) -> Void)?
    private let lock = NSLock()
    init(_ reply: @escaping (String?) -> Void) { self.reply = reply }
    func send(_ value: String?) {
        lock.lock(); let r = reply; reply = nil; lock.unlock()
        r?(value)
    }
}
