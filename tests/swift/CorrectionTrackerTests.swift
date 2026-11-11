// ergou-ime — tests for CorrectionTracker (ErgouIME/Speech/CorrectionTracker.swift).
// SPDX-License-Identifier: GPL-3.0-only
//
// The inserted text is "用 Orca 看一下" rather than the plan's "用 Orca 看",
// so that Orca → rea stays within the learn-diff limits (changed ≤ half).

import Foundation

/// A text field backed by a String; counts reads.
private final class FakeField: CorrectionField {
    var buffer: String
    var readable = true
    var hasMarkedText = false
    var reads = 0

    init(_ buffer: String) { self.buffer = buffer }

    var length: Int { buffer.utf16.count }
    var identity: ObjectIdentifier { ObjectIdentifier(self) }

    func text(in range: NSRange) -> String? {
        reads += 1
        guard readable else { return nil }
        let ns = buffer as NSString
        guard range.location >= 0, range.location + range.length <= ns.length else { return nil }
        return ns.substring(with: range)
    }

    /// UTF-16 offset of `part` in the buffer.
    func offset(of part: String) -> Int { (buffer as NSString).range(of: part).location }
}

private func pair(_ heard: String, _ term: String) -> CorrectionPair { CorrectionPair(heard: heard, term: term) }

/// A tracker with a settable clock and a log of every onEvents call.
private final class Harness {
    var time: TimeInterval = 100
    var enabled = true
    var secure = false
    var calls: [[CorrectionEvent]] = []
    lazy var tracker = CorrectionTracker(
        onEvents: { [unowned self] in self.calls.append($0) },
        now: { [unowned self] in self.time },
        isEnabled: { [unowned self] in self.enabled },
        isSecure: { [unowned self] in self.secure })
}

private let inserted = "用 Orca 看一下"
private let edited = "用 rea 看一下"

/// "x" + inserted, tracking started on the inserted part.
private func started(_ h: Harness, after: String = "") -> FakeField {
    let f = FakeField("x" + inserted + after)
    h.tracker.begin(field: f, start: 1, inserted: inserted, applied: [])
    return f
}

let correctionTrackerTests: [Test] = [
    ("learnsOnFinish", {
        let h = Harness()
        let f = started(h)
        f.buffer = "x" + edited
        h.tracker.finish(field: f, reason: .completionKey)
        expect(h.calls, [[.learn(pair("Orca", "rea"))]], "learned once")
    }),
    ("learnsWithTextAfter", {
        // Text after the insertion bounds the region (anchorAfter).
        let h = Harness()
        let f = started(h, after: "。下一句也在这里")
        f.buffer = "x" + edited + "。下一句也在这里"
        h.tracker.finish(field: f, reason: .focusLost)
        expect(h.calls, [[.learn(pair("Orca", "rea"))]], "region ends before anchorAfter")
    }),
    ("finishOnReturnComparesFirst", {
        let h = Harness()
        let f = started(h)
        f.buffer = "x" + edited
        h.tracker.finish(field: f, reason: .completionKey)
        f.buffer = ""  // the app handles Return (e.g. a chat box sends and clears)
        h.tracker.finish(field: f, reason: .completionKey)
        h.tracker.keyHandled(field: f)
        expect(h.calls, [[.learn(pair("Orca", "rea"))]], "read before the key went on; once")
    }),
    ("anchorLostLearnsNothing", {
        let h = Harness()
        let f = started(h)
        f.buffer = "完全不同的另一段文字"
        h.tracker.finish(field: f, reason: .completionKey)
        expect(h.calls, [], "anchor gone")
    }),
    ("anchorLostOnIntermediateReadStops", {
        let h = Harness()
        let f = started(h)
        f.buffer = "x" + edited
        h.time += 2
        h.tracker.keyHandled(field: f)  // good region with the edit
        f.buffer = "y" + edited
        h.time += 2
        h.tracker.keyHandled(field: f)  // anchor lost: stop
        f.buffer = "x" + edited
        h.tracker.finish(field: f, reason: .completionKey)
        expect(h.calls, [], "nothing learned after the anchor was lost")
    }),
    ("failedFinalReadUsesLastGood", {
        let h = Harness()
        let f = started(h)
        f.buffer = "x" + edited
        h.time += 2
        h.tracker.keyHandled(field: f)
        f.readable = false
        h.tracker.finish(field: f, reason: .focusLost)
        expect(h.calls, [[.learn(pair("Orca", "rea"))]], "last good region")
    }),
    ("unreadableClientNoTracking", {
        let h = Harness()
        let f = FakeField("x" + inserted)
        f.readable = false
        h.tracker.begin(field: f, start: 1, inserted: inserted, applied: [])
        f.readable = true
        f.buffer = "x" + edited
        h.time += 2
        h.tracker.keyHandled(field: f)
        h.tracker.finish(field: f, reason: .completionKey)
        expect(h.calls, [], "not tracked")
        expect(f.reads, 1, "only the attempt in begin")
    }),
    ("disabledNoTracking", {
        let h = Harness()
        h.enabled = false
        let f = started(h)
        f.buffer = "x" + edited
        h.tracker.finish(field: f, reason: .completionKey)
        expect(h.calls, [], "switch off")
        expect(f.reads, 0, "never read")
    }),
    ("secureNoTracking", {
        let h = Harness()
        h.secure = true
        let f = started(h)
        f.buffer = "x" + edited
        h.tracker.finish(field: f, reason: .completionKey)
        expect(h.calls, [], "secure input")
        expect(f.reads, 0, "never read")
    }),
    ("secureMidwayDrops", {
        let h = Harness()
        let f = started(h)
        f.buffer = "x" + edited
        h.time += 2
        h.tracker.keyHandled(field: f)
        h.secure = true
        let before = f.reads
        h.tracker.finish(field: f, reason: .completionKey)
        expect(h.calls, [], "dropped")
        expect(f.reads, before, "no read while secure")
    }),
    ("timeoutEnds", {
        let h = Harness()
        let f = started(h)
        f.buffer = "x" + edited
        h.time += 2
        h.tracker.keyHandled(field: f)
        h.time += 61
        let before = f.reads
        h.tracker.keyHandled(field: f)
        expect(h.calls, [[.learn(pair("Orca", "rea"))]], "emitted on timeout")
        expect(f.reads, before, "no read after maxDuration")
        h.tracker.finish(field: f, reason: .completionKey)
        expect(h.calls.count, 1, "later finish emits nothing")
    }),
    ("throttledReads", {
        let h = Harness()
        let f = started(h)
        f.reads = 0
        for _ in 0..<10 {
            h.time += 0.1
            h.tracker.keyHandled(field: f)
        }
        check(f.reads <= 2, "read at most twice in 1 s (got \(f.reads))")
    }),
    ("markedTextSkipsRead", {
        let h = Harness()
        let f = started(h)
        f.reads = 0
        f.hasMarkedText = true
        h.time += 5
        h.tracker.keyHandled(field: f)
        expect(f.reads, 0, "no read with marked text")
    }),
    ("otherFieldJustStops", {
        let h = Harness()
        let f = started(h)
        f.buffer = "x" + edited
        h.tracker.finish(field: FakeField("x" + edited), reason: .focusLost)
        h.tracker.finish(field: f, reason: .completionKey)
        expect(h.calls, [], "other field: stop without events")
    }),
    ("newInsertionEndsPrevious", {
        let h = Harness()
        let f = started(h)
        f.buffer = "x" + edited
        let second = "，好的我们开始吧"
        f.buffer += second
        h.tracker.begin(field: f, start: f.offset(of: second), inserted: second, applied: [])
        expect(h.calls, [[.learn(pair("Orca", "rea"))]], "A's events first")
        h.tracker.finish(field: f, reason: .completionKey)
        expect(h.calls.count, 1, "B unchanged: no call")
    }),
    ("utf16Offsets", {
        // An emoji before the insertion is 2 UTF-16 units.
        let h = Harness()
        let f = FakeField("😀" + inserted)
        h.tracker.begin(field: f, start: 2, inserted: inserted, applied: [])
        f.buffer = "😀" + edited
        h.tracker.finish(field: f, reason: .completionKey)
        expect(h.calls, [[.learn(pair("Orca", "rea"))]], "UTF-16 start")
    }),
    ("appliedRuleRevertVetoes", {
        let h = Harness()
        let text = "我们用 rea 看一下这个"
        let f = FakeField("x" + text)
        h.tracker.begin(field: f, start: 1, inserted: text, applied: [pair("Orca", "rea")])
        f.buffer = "x我们用 Orca 看一下这个"
        h.tracker.finish(field: f, reason: .completionKey)
        check(h.calls.first?.contains(.veto(pair("Orca", "rea"))) == true, "veto passed through (got \(h.calls))")
    }),
]
