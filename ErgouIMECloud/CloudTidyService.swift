// ErgouIME Cloud — XPC service for the cloud tidy-up.
// SPDX-License-Identifier: GPL-3.0-only
//
// The only part of ergou-ime that may reach the network on its own
// (Shared/Privacy.swift rule 11). Sandboxed; entitlements: network.client
// and the App Group, nothing else. The input method launches it only when
// 自动整理 is set to 云端. It reads the provider settings from the shared
// defaults and the key from CloudKeyFile on every call (nothing cached), and
// exits after 5 idle minutes.

import Foundation
import os

final class CloudTidyService: NSObject, CloudXPC {
    static let shared = CloudTidyService()

    private let log = Logger(subsystem: "com.codamon.inputmethod.Ergou.Cloud", category: "cloud")
    private var idleTimer: DispatchSourceTimer?
    private static let idleExit: TimeInterval = 5 * 60
    /// Requests still running, by recording (CloudTidy.Request.batch).
    private let callsLock = NSLock()
    private var calls: [Int: [ObjectIdentifier: CloudCall]] = [:]

    func tidy(_ request: Data, reply: @escaping (Data?) -> Void) {
        touch()
        guard request.count < 64 << 10,
              let r = try? JSONDecoder().decode(CloudTidy.Request.self, from: request),
              !r.text.isEmpty, r.text.count <= 2000 else {
            reply(Self.encode(CloudTidy.Reply(failure: .badRequest)))
            return
        }
        // The input method checks this too; dictation goes out only in 云端 mode (rule 11).
        guard SharedSettings.voiceCorrection == .cloud else {
            reply(Self.encode(CloudTidy.Reply(failure: .badConfig)))
            return
        }
        run(r, kind: "tidy", reply: reply)
    }

    func test(reply: @escaping (Data?) -> Void) {
        touch()
        run(CloudTidy.Request(text: CloudTidy.testSentence, context: nil, app: nil,
                              terms: ["Claude", "GPT"], timeout: CloudTidy.timeout),
            kind: "test", reply: reply)
    }

    func cancel(batch: Int) {
        callsLock.lock()
        let running = calls.removeValue(forKey: batch)
        callsLock.unlock()
        running?.values.forEach { $0.cancel() }
        if let running, !running.isEmpty {
            log.notice("cancelled \(running.count, privacy: .public) requests")
        }
    }

    private func register(_ call: CloudCall, batch: Int?) {
        guard let batch else { return }
        callsLock.lock(); calls[batch, default: [:]][ObjectIdentifier(call)] = call; callsLock.unlock()
    }

    private func unregister(_ call: CloudCall, batch: Int?) {
        guard let batch else { return }
        callsLock.lock()
        calls[batch]?[ObjectIdentifier(call)] = nil
        if calls[batch]?.isEmpty == true { calls[batch] = nil }
        callsLock.unlock()
    }

    private func run(_ r: CloudTidy.Request, kind: String, reply: @escaping (Data?) -> Void) {
        guard let config = CloudConfig.current else {
            reply(Self.encode(CloudTidy.Reply(failure: .badConfig))); return
        }
        guard let key = CloudKeyFile.load(config.provider) else {
            reply(Self.encode(CloudTidy.Reply(failure: .noKey))); return
        }
        let chars = r.text.count, contextChars = r.context?.count ?? 0, terms = r.terms.count
        let call = CloudCall()
        register(call, batch: r.batch)
        CloudClient(config: config, key: key).tidy(r, call: call) { [log, weak self] result in
            self?.unregister(call, batch: r.batch)
            // Counts and timing only — never text, context, terms or the key.
            log.notice("\(kind, privacy: .public) \(config.provider.rawValue, privacy: .public): status \(result.status, privacy: .public), \(result.failure?.rawValue ?? "ok", privacy: .public), \(result.ms, privacy: .public) ms, \(chars, privacy: .public) chars in, \(result.text?.count ?? 0, privacy: .public) out, context \(contextChars, privacy: .public), terms \(terms, privacy: .public) sent / \(result.terms.count, privacy: .public) back")
            reply(Self.encode(result))
        }
    }

    private static func encode(_ r: CloudTidy.Reply) -> Data? { try? JSONEncoder().encode(r) }

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
