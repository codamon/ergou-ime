// ErgouIME Cloud — one tidy-up request to the chosen provider.
// SPDX-License-Identifier: GPL-3.0-only
//
// Also compiled by tools/cloud-bench (real calls from the command line).
// Never logs text, context, terms or the key: only status, time and counts.

import Foundation

struct CloudClient {
    let config: CloudConfig
    let key: String
    /// Called once per HTTP request after it finished (the structured try and
    /// the plain retry are two requests): request, status, response bytes,
    /// error. ErgouIME Cloud records it in 联网记录 (NetworkLog).
    var onRequest: ((URLRequest, Int?, Int, Error?) -> Void)? = nil

    static let anthropicURL = URL(string: "https://api.anthropic.com/v1/messages")!
    static let anthropicVersion = "2023-06-01"
    static let maxResponseBytes = 1 << 20

    /// Ephemeral: no cookies, no cache, no credential storage on disk.
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.httpShouldSetCookies = false
        c.waitsForConnectivity = false
        return URLSession(configuration: c, delegate: NoRedirects(), delegateQueue: nil)
    }()

    /// Redirects are refused: a 307/308 would re-send the dictated text
    /// (and possibly the API key) to a host the user did not choose, while
    /// 联网记录 showed the original one (audit 0.4.1 M6; Privacy rule 11:
    /// "to the provider the user chose, nowhere else"). The 3xx answer is
    /// then the response, reported as an HTTP error.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    /// Calls `done` exactly once, on an arbitrary queue. `call.cancel()`
    /// stops it (reply `.cancelled`).
    func tidy(_ request: CloudTidy.Request, call: CloudCall = CloudCall(),
              done: @escaping (CloudTidy.Reply) -> Void) {
        let started = Date()
        let deadline = started.addingTimeInterval(max(1, min(request.timeout, 60)))
        let once = Once(done)
        func finish(_ reply: CloudTidy.Reply) {
            var r = reply
            r.ms = Int(Date().timeIntervalSince(started) * 1000)
            once.send(r)
        }
        // Hard deadline even if URLSession does not give up in time.
        DispatchQueue.global().asyncAfter(deadline: .now() + deadline.timeIntervalSinceNow + 0.2) {
            finish(CloudTidy.Reply(failure: .timeout))
        }
        send(request, structured: true, deadline: deadline, call: call) { result in
            switch result {
            case .failure(let reply) where reply.failure == .http && reply.status == 400 && Date() < deadline - 1
                && !call.isCancelled:
                // Some services / models reject response_format or this thinking setting: once more, plain.
                self.send(request, structured: false, deadline: deadline, call: call) { finish($0.reply(input: request.text, app: request.app)) }
            default:
                finish(result.reply(input: request.text, app: request.app))
            }
        }
    }

    enum Outcome {
        case success(String, Int)
        case failure(CloudTidy.Reply)

        func reply(input: String, app: String? = nil) -> CloudTidy.Reply {
            switch self {
            case .failure(let r):
                return r
            case .success(let output, let status):
                guard let parsed = CloudTidy.parse(output, input: input, app: app) else {
                    let failure: CloudTidy.Failure = CloudTidy.jsonObject(output) == nil ? .badJSON : .rejected
                    return CloudTidy.Reply(status: status, failure: failure)
                }
                return CloudTidy.Reply(text: parsed.text, terms: parsed.terms, status: status)
            }
        }
    }

    private func send(_ request: CloudTidy.Request, structured: Bool, deadline: Date, call: CloudCall,
                      done: @escaping (Outcome) -> Void) {
        let left = deadline.timeIntervalSinceNow
        guard left > 0.3 else { done(.failure(CloudTidy.Reply(failure: .timeout))); return }
        guard let urlRequest = makeRequest(request, structured: structured, timeout: left) else {
            done(.failure(CloudTidy.Reply(failure: .badConfig))); return
        }
        let task = Self.session.dataTask(with: urlRequest) { [onRequest] data, response, error in
            onRequest?(urlRequest, (response as? HTTPURLResponse)?.statusCode, data?.count ?? 0, error)
            if let error = error as? URLError {
                let failure: CloudTidy.Failure = error.code == .cancelled ? .cancelled
                    : error.code == .timedOut ? .timeout : .network
                done(.failure(CloudTidy.Reply(failure: failure)))
                return
            }
            guard error == nil, let http = response as? HTTPURLResponse, let data else {
                done(.failure(CloudTidy.Reply(failure: .network))); return
            }
            guard (200..<300).contains(http.statusCode) else {
                done(.failure(CloudTidy.Reply(status: http.statusCode, failure: .http))); return
            }
            // A tidy-up answer is a few KB; do not parse whatever a server sends.
            guard data.count <= Self.maxResponseBytes else {
                done(.failure(CloudTidy.Reply(status: http.statusCode, failure: .badJSON))); return
            }
            switch self.output(data) {
            case .some(.some(let text)): done(.success(text, http.statusCode))
            case .some(.none): done(.failure(CloudTidy.Reply(status: http.statusCode, failure: .refused)))
            case .none: done(.failure(CloudTidy.Reply(status: http.statusCode, failure: .badJSON)))
            }
        }
        guard call.attach(task) else { done(.failure(CloudTidy.Reply(failure: .cancelled))); return }
        task.resume()
    }

    /// A relay with the Anthropic API: <base>/messages, like the OpenAI-compatible
    /// rule (base given up to /v1). A bare host gets /v1/messages, the full
    /// endpoint is kept.
    static func anthropicEndpoint(_ base: URL) -> URL {
        if base.path.hasSuffix("/messages") { return base }
        if base.path.isEmpty || base.path == "/" { return base.appendingPathComponent("v1/messages") }
        return base.appendingPathComponent("messages")
    }

    /// Thinking off: the tidy-up is a one-line edit, and thinking costs
    /// 1.5–2 s (D's Mac, 2026-11-10: Haiku 5.5 with thinking disabled ≈ 1.0 s
    /// a sentence, adaptive + effort low 2.4–3.1 s). Sonnet 5.5 rejects
    /// "disabled" and takes "between_tools" (= no thinking without tools).
    /// Any other model that rejects "disabled" gets a 400 and the plain retry.
    static func thinkingOff(model: String) -> [String: Any] {
        model.contains("sonnet-5-5") ? ["type": "between_tools"] : ["type": "disabled"]
    }

    func makeRequest(_ r: CloudTidy.Request, structured: Bool, timeout: TimeInterval) -> URLRequest? {
        let user = CloudTidy.userMessage(r)
        var body: [String: Any]
        let url: URL
        switch config.provider {
        case .anthropic:
            url = config.baseURL.map(Self.anthropicEndpoint) ?? Self.anthropicURL
            body = [
                "model": config.model,
                "max_tokens": 4096,
                "system": CloudTidy.system,
                "messages": [["role": "user", "content": user]],
            ]
            // JSON is asked for in the prompt (CloudTidy.system rule 7) and
            // parsed leniently; a json_schema output format adds 0.3–1 s.
            // No effort: Haiku 5.5's default (medium) allows thinking off.
            if structured { body["thinking"] = Self.thinkingOff(model: config.model) }
        case .openAICompatible:
            guard let base = config.baseURL else { return nil }
            url = base.path.hasSuffix("/chat/completions") ? base : base.appendingPathComponent("chat/completions")
            body = [
                "model": config.model,
                "messages": [["role": "system", "content": CloudTidy.system],
                             ["role": "user", "content": user]],
            ]
            if structured { body["response_format"] = ["type": "json_object"] }
        }
        guard url.scheme == "https", let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.httpBody = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch config.provider {
        case .anthropic:
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        case .openAICompatible:
            req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        }
        return req
    }

    /// The model's text: nil = not the response shape we know;
    /// .some(nil) = refused / cut off.
    func output(_ data: Data) -> String?? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch config.provider {
        case .anthropic:
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            let stop = json["stop_reason"] as? String
            if stop == "refusal" || stop == "max_tokens" { return .some(nil) }
            let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? .some(nil) : .some(text)
        case .openAICompatible:
            guard let choice = (json["choices"] as? [[String: Any]])?.first,
                  let message = choice["message"] as? [String: Any] else { return nil }
            if choice["finish_reason"] as? String == "length" { return .some(nil) }
            guard let text = message["content"] as? String, !text.isEmpty else { return .some(nil) }
            return .some(text)
        }
    }
}

/// Calls the completion exactly once.
private final class Once: @unchecked Sendable {
    private var done: ((CloudTidy.Reply) -> Void)?
    private let lock = NSLock()
    init(_ done: @escaping (CloudTidy.Reply) -> Void) { self.done = done }
    func send(_ value: CloudTidy.Reply) {
        lock.lock(); let d = done; done = nil; lock.unlock()
        d?(value)
    }
}

/// One tidy-up request that can be cancelled from another thread (CloudXPC.cancel).
final class CloudCall: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    init() {}

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    /// False if cancelled already (the task is then not started).
    func attach(_ t: URLSessionTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        task = t
        return true
    }

    func cancel() {
        lock.lock(); cancelled = true; let t = task; lock.unlock()
        t?.cancel()
    }
}
