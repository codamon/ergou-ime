// ergou-ime — cloud tidy-up while the user is still speaking.
// SPDX-License-Identifier: GPL-3.0-only
//
// 自动整理 = 云端 (docs/PLAN-v1.md M2.7). VoiceSession cuts a dictation into
// segments at pauses and recognises each one while recording. Each
// segment's final text (Qwen3-ASR, or SenseVoice) goes to the cloud as soon
// as it is recognised, so when the user stops only the last segment is
// still out: the wait after speaking drops from 4–11 s (whole text at the
// end) to about 1 s (D's Mac, 2026-11-10).
//
// Each request carries, as context, the last CloudTidy.maxContext
// characters of: the text before the cursor (only if the user allows it,
// CloudTidy.contextAllowed) + this dictation's earlier segments (tidied
// where back already, else as recognised). A segment over 300 characters is
// split like the local engines (CorrectorClient.chunks).
//
// Results are stored by segment number, so replies arriving out of order
// are still joined in order. finish() waits at most CloudTidy.finishWait for
// segments still out; those, and any that fail, are typed as recognised.
// skip() (Return / Right Option while 整理中) finishes at once the same way:
// segments already tidied keep the tidied text — they are better and cost
// no more waiting — the others are typed as recognised.
//
// No networking here (scripts/check-no-network.sh): `send` hands a request
// to ErgouIME Cloud (CloudCorrector) or, in tools/cloud-bench, straight to
// CloudClient. Main queue only; `send` must call back on the main queue.

import Foundation

final class CloudStream {
    typealias Send = (CloudTidy.Request, @escaping (CloudTidy.Reply?) -> Void) -> Void

    struct Result {
        var text: String
        /// Segments with at least one tidied chunk / all segments.
        var tidied: Int
        var segments: Int
        /// Validated terms from the tidied chunks that were used.
        var terms: [CloudTidy.Term]
    }

    let batch: Int
    private let before: String?
    private let app: String?
    private let terms: [String]
    private let timeout: TimeInterval
    private let send: Send

    private struct Segment {
        var text: String
        var chunks: [String]
        var outputs: [String?]
        var terms: [[CloudTidy.Term]]
        var left: Int
        var serial: Int
        /// Tidied chunks where back, recognised text for the rest.
        var best: String { zip(chunks, outputs).map { $1 ?? $0 }.joined() }
        var isTidied: Bool { outputs.contains { $0 != nil } }
    }

    private var segments: [Int: Segment] = [:]
    private var serial = 0
    private var ended = false
    private var finishing: ((Result) -> Void)?
    private var finishTimer: DispatchWorkItem?

    /// Called on every reply while finishing (for the HUD).
    var onUpdate: (() -> Void)?

    /// `before`: text before the cursor, nil when not allowed. `terms`: 我的词.
    init(batch: Int, before: String?, app: String?, terms: [String],
         timeout: TimeInterval = CloudTidy.timeout, send: @escaping Send) {
        self.batch = batch
        self.before = before
        self.app = app
        self.terms = Array(terms.prefix(CloudTidy.maxSentTerms))
        self.timeout = timeout
        self.send = send
    }

    /// The joined result once more, as one request (CloudTidy.wholeRule):
    /// same app, 我的词 and text before the cursor as the segments had.
    func wholeRequest(_ text: String) -> CloudTidy.Request {
        let context = CloudTidy.contextTail(before ?? "")
        return CloudTidy.Request(text: text, context: context.isEmpty ? nil : context, app: app, terms: terms,
                                 timeout: CloudTidy.wholeTimeout, batch: batch, whole: true)
    }

    /// Segments whose requests have not all come back.
    var pending: Int { segments.values.filter { $0.left > 0 }.count }

    /// A segment's final recognised text: send it now. The same text again
    /// is ignored; a different one replaces the earlier request.
    func submit(_ index: Int, _ text: String) {
        guard !ended else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { segments[index] = nil; return }
        if segments[index]?.text == t { return }
        serial += 1
        let mine = serial
        let chunks = CorrectorClient.chunks(t, limit: 300)
        segments[index] = Segment(text: t, chunks: chunks, outputs: Array(repeating: nil, count: chunks.count),
                                  terms: Array(repeating: [], count: chunks.count), left: chunks.count, serial: mine)
        var prefix = (before ?? "") + earlier(than: index)
        for (k, chunk) in chunks.enumerated() {
            let context = CloudTidy.contextTail(prefix)
            prefix += chunk
            let request = CloudTidy.Request(text: chunk, context: context.isEmpty ? nil : context,
                                            app: app, terms: terms, timeout: timeout, batch: batch)
            send(request) { [weak self] reply in self?.received(reply, index: index, chunk: k, serial: mine) }
        }
    }

    /// The text this dictation has before segment `index`.
    private func earlier(than index: Int) -> String {
        segments.keys.filter { $0 < index }.sorted().map { segments[$0]!.best }.joined()
    }

    private func received(_ reply: CloudTidy.Reply?, index: Int, chunk k: Int, serial mine: Int) {
        // Cancelled, finished, or replaced by a newer text for this segment: drop it.
        guard !ended, var s = segments[index], s.serial == mine, k < s.chunks.count else { return }
        let input = s.chunks[k]
        // Re-checked here: the service has network access, its answers are untrusted.
        if let t = reply?.text, CorrectionPrompt.lengthOK(t, for: input), !CloudTidy.containsTag(t) {
            s.outputs[k] = t
            let raw: [Any] = reply?.terms.map { ["term": $0.term, "heard": $0.heard ?? ""] } ?? []
            s.terms[k] = CloudTidy.terms(raw, text: t, input: input)
        }
        s.left -= 1
        segments[index] = s
        guard finishing != nil else { return }
        onUpdate?()
        if pending == 0 { complete() }
    }

    /// What to show for each recognised segment: tidied where back.
    func shown(_ recognised: [String?]) -> String {
        recognised.enumerated().compactMap { i, raw in
            if let s = segments[i], s.isTidied { return s.best }
            return raw
        }.joined()
    }

    /// Recording stopped and recognised: `texts` has one entry per segment
    /// (nil: nothing recognised). Sends what has not been sent, then calls
    /// `done` once on the main queue — when every segment is back, or after
    /// `wait` seconds, or on skip().
    func finish(_ texts: [String?], wait: TimeInterval = CloudTidy.finishWait, done: @escaping (Result) -> Void) {
        guard !ended else { return }
        for i in segments.keys where i >= texts.count { segments[i] = nil }
        finishing = done
        for (i, t) in texts.enumerated() {
            if let t { submit(i, t) } else { segments[i] = nil }
        }
        guard !ended, finishing != nil else { return }
        if pending == 0 { complete(); return }
        let timer = DispatchWorkItem { [weak self] in self?.complete() }
        finishTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: timer)
    }

    /// While finishing: type what is there now. False if not finishing.
    @discardableResult
    func skip() -> Bool {
        guard finishing != nil else { return false }
        complete()
        return true
    }

    /// Esc: drop everything; replies still out are ignored.
    func cancel() {
        ended = true
        finishing = nil
        finishTimer?.cancel()
        segments = [:]
    }

    private func complete() {
        guard let done = finishing else { return }
        finishing = nil
        finishTimer?.cancel()
        ended = true
        let order = segments.keys.sorted()
        let used = order.map { segments[$0]! }
        let terms = used.flatMap { s in zip(s.outputs, s.terms).filter { $0.0 != nil }.flatMap { $0.1 } }
        done(Result(text: used.map(\.best).joined(), tidied: used.filter(\.isTidied).count,
                    segments: used.count, terms: terms))
    }
}
