// ergou-ime — 从我的修改里学习: connects the tracker to the stores and the IMK client.
// SPDX-License-Identifier: GPL-3.0-only
//
// The controller calls begin after a voice insertion (not for ForeignInsert
// or the 语音记录 window), finish on Return / Tab / Esc (synchronously, before
// the key reaches the app) and when focus leaves, and keyHandledSoon after
// every key while tracking (the read runs on the next main-queue turn). A
// one-shot timer ends tracking at CorrectionTracker.maxDuration even if no
// key comes.
//
// Events (CorrectionRouting.route): learn → 我的词 (TermStore, source
// .edit, with the heard side) and, only if the term is now in 我的词,
// CorrectionStore (counts the sighting; a rule from the second one);
// hotword → 我的词 only; veto → CorrectionStore. Only counts are logged.
//
// Privacy (Shared/Privacy.swift rule 12): everything stays in this process;
// the field text read here lives in the tracker's memory until tracking
// ends; nothing is read in secure input.

import AppKit
import InputMethodKit

enum CorrectionLearning {
    static let tracker = CorrectionTracker(onEvents: handle, isSecure: { SecureInput.isActive })

    private static var timer: DispatchWorkItem?
    /// Counts begin calls, so a queued keyHandled from before a new voice
    /// insertion does not touch the new tracking.
    private static var session = 0
    private static var queued = false

    /// Call right after the voice text is in the field.
    static func begin(field: CorrectionField, start: Int, inserted: String, applied: [CorrectionPair], app: String?) {
        session += 1
        let result = tracker.begin(field: field, start: start, inserted: inserted, applied: applied)
        Log.speech.notice("correction: \(result.rawValue, privacy: .public) in \(app ?? "?", privacy: .public)")
        rescheduleTimer()
    }

    /// After a key was handled (cheap when not tracking).
    static func keyHandled(field: CorrectionField) {
        guard tracker.isTracking else { return }
        tracker.keyHandled(field: field)
        if !tracker.isTracking { cancelTimer() }
    }

    /// keyHandled on the next main-queue turn: off the key path, and after
    /// the app has applied the key. At most one is queued at a time.
    static func keyHandledSoon(field: CorrectionField) {
        guard tracker.isTracking, !queued else { return }
        queued = true
        let mine = session
        DispatchQueue.main.async {
            queued = false
            guard mine == session else { return }
            keyHandled(field: field)
        }
    }

    static func finish(field: CorrectionField?, reason: CorrectionTracker.EndReason) {
        guard tracker.isTracking else { return }
        tracker.finish(field: field, reason: reason)
        cancelTimer()
    }

    static func handle(_ events: [CorrectionEvent]) {
        let (learned, vetoed) = CorrectionRouting.route(
            events,
            recordTerm: { TermStore.shared.record(term: $0, heard: $1, source: .edit) },
            learn: { CorrectionStore.shared.learn($0) },
            veto: { CorrectionStore.shared.veto($0) })
        Log.speech.notice("correction: learned \(learned, privacy: .public), vetoed \(vetoed, privacy: .public)")
    }

    private static func rescheduleTimer() {
        cancelTimer()
        guard tracker.isTracking else { return }
        let item = DispatchWorkItem {
            timer = nil
            tracker.expire()
        }
        timer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + CorrectionTracker.maxDuration, execute: item)
    }

    private static func cancelTimer() {
        timer?.cancel()
        timer = nil
    }
}

/// The IMK client as a CorrectionField. Created per call; holds the client
/// weakly, so a client that went away reads as unknown instead of being kept
/// alive by the tracker.
final class ClientField: CorrectionField {
    private weak var client: IMKTextInput?
    let identity: ObjectIdentifier

    init(_ client: IMKTextInput) {
        self.client = client
        identity = ObjectIdentifier(client as AnyObject)
    }

    var length: Int {
        guard let client else { return NSNotFound }
        let n = client.length()
        return n >= 0 ? n : NSNotFound
    }

    func text(in range: NSRange) -> String? {
        guard let client, range.location != NSNotFound, range.location >= 0, range.length >= 0 else { return nil }
        return client.attributedSubstring(from: range)?.string
    }

    var hasMarkedText: Bool {
        guard let client else { return false }
        let r = client.markedRange()
        return r.location != NSNotFound && r.length > 0
    }
}
