// ergou-ime — cloud-bench: the cloud tidy-up's request and parsing code,
// run from the command line against a real provider, plus offline checks.
// SPDX-License-Identifier: GPL-3.0-only
//
//   .cloud-bench tests
//   .cloud-bench call <anthropic|openai> <base-url|-> <model> <in.txt> <out.txt> [context.txt|-] [terms] [timeout]
//   .cloud-bench simulate <anthropic|openai> <base-url|-> <model> <segs.tsv> <out.txt> [context.txt|-] [terms] [timeout] [wait]
//
// <base-url>: OpenAI-compatible base (…/v1), or for anthropic a relay base
// ("-" = the official API).
//
// `call` reads the API key from standard input (never from the command
// line, never printed), splits the text like the input method (300
// characters), sends all chunks at once (context with the first only) and
// writes the joined result to out.txt. It prints status, time, characters
// and the terms per chunk — like the service's log, plus the terms.
//
// `simulate` replays a dictation through CloudStream, the input method's
// tidy-up-while-speaking code: segs.tsv has one line per segment,
// "<seconds of audio>\t<recognised text>" (empty text: nothing recognised).
// Segment i counts as recognised when the audio up to its end has been
// spoken (real-time pacing), and is sent then; after the last one,
// CloudStream.finish waits (at most `wait`, default CloudTidy.finishWait).
// Prints each segment's request time and the wait after the last segment.

import Foundation

let args = CommandLine.arguments

func die(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(2) }

switch args.count > 1 ? args[1] : "" {
case "tests":
    setvbuf(stdout, nil, _IONBF, 0)
    exit(runCloudTests() ? 0 : 1)

case "call":
    guard args.count >= 7 else { die("usage: call <provider> <base|-> <model> <in> <out> [context|-] [terms] [timeout]") }
    guard let provider = CloudProvider(rawValue: args[2]) else { die("provider: anthropic or openai") }
    let base = args[3] == "-" ? nil : CloudConfig.validBaseURL(args[3])
    if (provider == .openAICompatible || args[3] != "-"), base == nil { die("bad base URL") }
    guard let model = CloudConfig.validModel(args[4]) else { die("bad model") }
    guard let text = try? String(contentsOfFile: args[5], encoding: .utf8) else { die("cannot read input") }
    let context = args.count > 7 && args[7] != "-" ? (try? String(contentsOfFile: args[7], encoding: .utf8)) : nil
    let terms = args.count > 8 ? args[8].split(separator: ",").map(String.init) : []
    let timeout = args.count > 9 ? Double(args[9]) ?? CloudTidy.timeout : CloudTidy.timeout
    guard let line = readLine(strippingNewline: true), let key = CloudKeyFile.valid(line) else { die("no key on stdin") }

    let client = CloudClient(config: CloudConfig(provider: provider, baseURL: base, model: model), key: key)
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // WHOLE=1: the text as one request with CloudTidy.wholeRule (说完后再整理一遍全文).
    let whole = ProcessInfo.processInfo.environment["WHOLE"] == "1"
    let chunks = whole ? [input] : CorrectorClient.chunks(input, limit: 300)
    var replies = [CloudTidy.Reply?](repeating: nil, count: chunks.count)
    let group = DispatchGroup()
    let lock = NSLock()
    let started = Date()
    for (i, chunk) in chunks.enumerated() {
        group.enter()
        let r = CloudTidy.Request(text: chunk, context: i == 0 ? context.map(CloudTidy.contextTail) : nil,
                                  app: "备忘录", terms: terms, timeout: timeout, whole: whole ? true : nil)
        client.tidy(r) { reply in
            lock.lock(); replies[i] = reply; lock.unlock()
            group.leave()
        }
    }
    group.wait()
    let total = Int(Date().timeIntervalSince(started) * 1000)
    var out = ""
    for (i, chunk) in chunks.enumerated() {
        let r = replies[i]!
        out += r.text ?? chunk
        let terms = r.terms.map { t in t.heard.map { "\(t.term)←\($0)" } ?? t.term }.joined(separator: " ")
        print("chunk \(i + 1)/\(chunks.count): status \(r.status) \(r.failure?.rawValue ?? "ok") \(r.ms) ms, \(chunk.count) → \(r.text?.count ?? 0) chars; terms: \(terms)")
    }
    print("total \(total) ms, \(replies.filter { $0?.text != nil }.count)/\(chunks.count) chunks applied")
    do { try out.write(toFile: args[6], atomically: true, encoding: .utf8) } catch { die("cannot write output") }

case "simulate":
    guard args.count >= 7 else { die("usage: simulate <provider> <base|-> <model> <segs.tsv> <out> [context|-] [terms] [timeout] [wait]") }
    guard let provider = CloudProvider(rawValue: args[2]) else { die("provider: anthropic or openai") }
    let base = args[3] == "-" ? nil : CloudConfig.validBaseURL(args[3])
    if (provider == .openAICompatible || args[3] != "-"), base == nil { die("bad base URL") }
    guard let model = CloudConfig.validModel(args[4]) else { die("bad model") }
    guard let tsv = try? String(contentsOfFile: args[5], encoding: .utf8) else { die("cannot read segments") }
    let context = args.count > 7 && args[7] != "-" ? (try? String(contentsOfFile: args[7], encoding: .utf8)) : nil
    let terms = args.count > 8 ? args[8].split(separator: ",").map(String.init) : []
    let timeout = args.count > 9 ? Double(args[9]) ?? CloudTidy.timeout : CloudTidy.timeout
    let wait = args.count > 10 ? Double(args[10]) ?? CloudTidy.finishWait : CloudTidy.finishWait
    guard let line = readLine(strippingNewline: true), let key = CloudKeyFile.valid(line) else { die("no key on stdin") }
    let segs: [(Double, String?)] = tsv.split(separator: "\n", omittingEmptySubsequences: true).map { l in
        let parts = l.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        let text = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        return (Double(parts[0]) ?? 0, text.isEmpty ? nil : text)
    }
    simulate(CloudClient(config: CloudConfig(provider: provider, baseURL: base, model: model), key: key),
             segs, context: context.map(CloudTidy.contextTail), terms: terms, timeout: timeout, wait: wait, out: args[6])

default:
    die("usage: .cloud-bench tests | call … | simulate …")
}

func simulate(_ client: CloudClient, _ segs: [(Double, String?)], context: String?, terms: [String],
              timeout: TimeInterval, wait: TimeInterval, out: String) -> Never {
    let t0 = Date()
    func now() -> Double { Date().timeIntervalSince(t0) }
    var sending = -1
    var lines = [Int: [String]]()
    let stream = CloudStream(batch: 1, before: context, app: "备忘录", terms: terms, timeout: timeout) { request, done in
        let index = sending, sentAt = now()
        client.tidy(request) { reply in
            DispatchQueue.main.async {
                let terms = reply.terms.map { t in t.heard.map { "\(t.term)←\($0)" } ?? t.term }.joined(separator: " ")
                lines[index, default: []].append(String(format: "seg %02d sent at %5.1f s, back at %5.1f s: ", index + 1, sentAt, now())
                    + "status \(reply.status) \(reply.failure?.rawValue ?? "ok") \(reply.ms) ms, \(request.text.count) → \(reply.text?.count ?? 0) chars, context \(request.context?.count ?? 0); terms: \(terms)")
                done(reply)
            }
        }
    }
    // asyncAfter lets long delays slip by up to ~10% (timer leeway): own timers, 5 ms leeway.
    var timers: [DispatchSourceTimer] = []
    func at(_ t: Double, _ block: @escaping () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + t, leeway: .milliseconds(5))
        timer.setEventHandler(handler: block)
        timer.resume()
        timers.append(timer)
    }
    var end = 0.0
    for (i, seg) in segs.enumerated() {
        end += seg.0
        guard let text = seg.1, i < segs.count - 1 else { continue }
        at(end) { sending = i; stream.submit(i, text) }
    }
    let lastAt = end
    at(lastAt) {
        sending = segs.count - 1
        let stopped = now()
        stream.finish(segs.map(\.1), wait: wait) { result in
            let waited = Int((now() - stopped) * 1000)
            for i in lines.keys.sorted() { lines[i]!.forEach { print($0) } }
            print(String(format: "audio %.1f s, %d segments; last segment recognised at %.1f s", lastAt, segs.count, stopped))
            print("wait after the last segment: \(waited) ms; \(result.tidied)/\(result.segments) segments tidied, \(stream.pending) still out, \(result.terms.count) terms")
            do { try result.text.write(toFile: out, atomically: true, encoding: .utf8) } catch { die("cannot write output") }
            exit(0)
        }
    }
    dispatchMain()
}
