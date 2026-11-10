// ergou-ime — the input method's side of the cloud tidy-up.
// SPDX-License-Identifier: GPL-3.0-only
//
// Hands one request (a segment's recognised text, or a ~300-character chunk
// of it, with its context, the app name and 我的词 — built by CloudStream) to
// ErgouIME Cloud over XPC. This process makes no network request and never
// reads the API key (Privacy rules 1 and 11). A request that fails or times
// out (CloudTidy.timeout) answers nil: CloudStream keeps the recognised text.

import AppKit

final class CloudCorrector {
    static let shared = CloudCorrector()

    private var connection: NSXPCConnection?
    private var observers: [NSObjectProtocol] = []

    /// Settings' 测试连接 (call once at start-up).
    func start() {
        observers.append(SharedNotifications.observe(SharedNotifications.cloudTest) { [weak self] in
            self?.runTest()
        })
    }

    private func proxy(onError: @escaping () -> Void) -> CloudXPC? {
        if connection == nil {
            let c = NSXPCConnection(serviceName: CloudService.name)
            c.remoteObjectInterface = NSXPCInterface(with: CloudXPC.self)
            // Only forget this connection, not one made since.
            let drop: () -> Void = { [weak self, weak c] in
                DispatchQueue.main.async { if let self, self.connection === c { self.connection = nil } }
            }
            c.invalidationHandler = drop
            c.interruptionHandler = drop
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in onError() } as? CloudXPC
    }

    /// What the user allowed to go with the text, taken when recording
    /// starts. Nothing in secure input.
    struct Context {
        var before: String?
        var app: String?
    }

    /// One request; `done` on the main queue with the reply or nil.
    func send(_ request: CloudTidy.Request, done: @escaping (CloudTidy.Reply?) -> Void) {
        let lock = NSLock()
        var finished = false
        let finish: (CloudTidy.Reply?) -> Void = { value in
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            DispatchQueue.main.async { done(value) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + request.timeout + 1) { finish(nil) }
        guard let data = try? JSONEncoder().encode(request),
              let remote = proxy(onError: { finish(nil) }) else { finish(nil); return }
        remote.tidy(data) { finish($0.flatMap { try? JSONDecoder().decode(CloudTidy.Reply.self, from: $0) }) }
    }

    /// Esc: stop the requests still running for this recording.
    func cancel(batch: Int) {
        guard connection != nil else { return }        // nothing was sent
        proxy(onError: {})?.cancel(batch: batch)
    }

    /// 测试连接: the service sends a fixed sentence; the outcome goes back to
    /// Settings through the shared defaults (no user data in it).
    private func runTest() {
        let defaults = Paths.sharedDefaults
        // Darwin notifications can come from any process: each id is used once.
        guard let id = defaults.string(forKey: SettingKey.cloudTestRequest), id.count <= 64 else { return }
        defaults.removeObject(forKey: SettingKey.cloudTestRequest)
        let report: (CloudTidy.Reply) -> Void = { reply in
            if let data = try? JSONEncoder().encode(CloudTestResult(id: id, reply: reply)) {
                defaults.set(String(decoding: data, as: UTF8.self), forKey: SettingKey.cloudTestResult)
            }
        }
        let lock = NSLock()
        var finished = false
        let finish: (CloudTidy.Reply) -> Void = { reply in
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            DispatchQueue.main.async { report(reply) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + CloudTidy.timeout + 2) {
            finish(CloudTidy.Reply(failure: .timeout))
        }
        guard let remote = proxy(onError: { finish(CloudTidy.Reply(failure: .network)) }) else {
            finish(CloudTidy.Reply(failure: .network)); return
        }
        remote.test { data in
            finish(data.flatMap { try? JSONDecoder().decode(CloudTidy.Reply.self, from: $0) }
                   ?? CloudTidy.Reply(failure: .badJSON))
        }
    }

    /// Readable name for a bundle id ("微信" for com.tencent.xinWeChat).
    static func appName(bundleID: String?) -> String? {
        guard let id = bundleID, !id.isEmpty else {
            return NSWorkspace.shared.frontmostApplication?.localizedName
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName ?? id
    }
}
