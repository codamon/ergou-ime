// ergou-ime — 语音纠正学习: watch a voice result in its field for a while.
// SPDX-License-Identifier: GPL-3.0-only
//
// After a voice insertion, the input method keeps an eye on the same text
// field (at most maxDuration, one insertion at a time). When tracking ends
// it reads the region where the insertion was and hands old and new text
// to EditCorrection.outcome; the events go to onEvents once.
//
// Finding the region again: at begin we remember up to anchorLength UTF-16
// units before the insertion and after it. Later reads take a window from
// the anchor before to a little past the insertion; the anchor before must
// still sit at the same offset (else the text moved: stop, learn nothing),
// and the region ends before the first occurrence of the anchor after.
//
// Privacy: field text is held in memory only while tracking and dropped
// when it ends; nothing is read while secure input is on, while marked
// text is up, or when 从修改中学习 (SharedSettings.learnFromEdits) is off.
// No logging of text. Main thread only. No InputMethodKit: the input
// method adapts its IMK client to CorrectionField.

import Foundation

/// The text field the voice result went into. Offsets are UTF-16 units.
protocol CorrectionField: AnyObject {
    /// UTF-16 length of the whole text; NSNotFound or 0 if unknown.
    var length: Int { get }
    /// nil: the app does not tell us.
    func text(in range: NSRange) -> String?
    var hasMarkedText: Bool { get }
    /// The underlying client; adapters are created per call.
    var identity: ObjectIdentifier { get }
}

final class CorrectionTracker {
    enum EndReason { case completionKey, focusLost, newInsertion, timeout }

    static let maxDuration: TimeInterval = 60
    static let minReadInterval: TimeInterval = 1
    /// UTF-16 units remembered on each side of the insertion.
    static let anchorLength = 16
    /// How far past the insertion a read looks (the user may type on).
    static let slack = 64

    private struct Tracking {
        let identity: ObjectIdentifier
        let start: Int
        let original: String
        let applied: [CorrectionPair]
        let anchorBefore: [UInt16]
        let anchorAfter: [UInt16]
        let startedAt: TimeInterval
        var lastRead: TimeInterval
        /// The region at the last read that found it.
        var lastGood: String
    }

    private let onEvents: ([CorrectionEvent]) -> Void
    private let now: () -> TimeInterval
    private let isEnabled: () -> Bool
    private let isSecure: () -> Bool
    private var tracking: Tracking?

    init(onEvents: @escaping ([CorrectionEvent]) -> Void,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         isEnabled: @escaping () -> Bool = { SharedSettings.learnFromEdits },
         isSecure: @escaping () -> Bool = { false }) {
        self.onEvents = onEvents
        self.now = now
        self.isEnabled = isEnabled
        self.isSecure = isSecure
    }

    var isTracking: Bool { tracking != nil }

    /// Call right after insertText. `start` = UTF-16 location where `inserted` begins.
    /// Ends the previous tracking first (with its final compare).
    func begin(field: CorrectionField, start: Int, inserted: String, applied: [CorrectionPair]) {
        if tracking != nil { finish(field: field, reason: .newInsertion) }
        let count = inserted.utf16.count
        let length = field.length
        guard isEnabled(), !isSecure(), !field.hasMarkedText, count > 0, start >= 0,
              length != NSNotFound, start + count <= length else { return }
        let lo = max(0, start - Self.anchorLength)
        let hi = min(length, start + count + Self.anchorLength)
        guard let window = field.text(in: NSRange(location: lo, length: hi - lo)).map({ Array($0.utf16) }),
              window.count == hi - lo else { return }
        let before = start - lo
        // The field must show what we typed (else an app changed it).
        guard Array(window[before..<(before + count)]) == Array(inserted.utf16) else { return }
        let t = now()
        tracking = Tracking(
            identity: field.identity, start: start, original: inserted, applied: applied,
            anchorBefore: Array(window[..<before]), anchorAfter: Array(window[(before + count)...]),
            startedAt: t, lastRead: t, lastGood: inserted)
    }

    /// After a key was handled: compare at most once per minReadInterval; ends on timeout.
    func keyHandled(field: CorrectionField) {
        guard let current = tracking else { return }
        guard current.identity == field.identity else { return stop() }
        if now() - current.startedAt > Self.maxDuration { return end() }
        guard now() - current.lastRead >= Self.minReadInterval else { return }
        refresh(field)
    }

    /// Final compare (if still tracking this field), then stop. nil field:
    /// no read, the last good region is used.
    func finish(field: CorrectionField?, reason: EndReason) {
        guard let current = tracking else { return }
        if let field {
            guard current.identity == field.identity else { return stop() }
            if now() - current.startedAt <= Self.maxDuration { refresh(field) }
        }
        end()
    }

    // MARK: - Internals

    /// Reads the region into lastGood. A failed read keeps the last good
    /// one; a lost anchor before or secure input stops tracking.
    private func refresh(_ field: CorrectionField) {
        guard var current = tracking else { return }
        guard isEnabled(), !isSecure() else { return stop() }
        guard !field.hasMarkedText else { return }
        current.lastRead = now()
        tracking = current
        let length = field.length
        guard length != NSNotFound else { return }
        let lo = current.start - current.anchorBefore.count
        let hi = min(length, current.start + current.original.utf16.count + Self.slack + current.anchorAfter.count)
        guard hi >= current.start else { return stop() }  // text before our start is gone
        guard let text = field.text(in: NSRange(location: lo, length: hi - lo)) else { return }
        let window = Array(text.utf16)
        guard window.count >= current.anchorBefore.count,
              Array(window[..<current.anchorBefore.count]) == current.anchorBefore else { return stop() }
        let rest = window[current.anchorBefore.count...]
        let end: Int
        if current.anchorAfter.isEmpty {
            end = rest.endIndex
        } else if let found = Self.firstIndex(of: current.anchorAfter, in: rest) {
            end = found
        } else {
            return  // typed past the window, or the text after changed: keep the last good
        }
        current.lastGood = String(decoding: rest[rest.startIndex..<end], as: UTF16.self)
        tracking = current
    }

    /// Compares the last good region with what was typed and stops.
    private func end() {
        guard let current = tracking else { return }
        stop()
        guard isEnabled(), !isSecure() else { return }
        let events = EditCorrection.outcome(original: current.original, current: current.lastGood, applied: current.applied)
        if !events.isEmpty { onEvents(events) }
    }

    /// Drops the state (and the field text it holds) without events.
    private func stop() { tracking = nil }

    private static func firstIndex(of needle: [UInt16], in hay: ArraySlice<UInt16>) -> Int? {
        guard needle.count <= hay.count else { return nil }
        var i = hay.startIndex
        while i + needle.count <= hay.endIndex {
            if hay[i..<(i + needle.count)].elementsEqual(needle) { return i }
            i += 1
        }
        return nil
    }
}
