// ergou-ime — 语音纠正学习: which word the user replaced in a voice result.
// SPDX-License-Identifier: GPL-3.0-only
//
// Pure logic, no state: given the text a voice insertion typed (original)
// and the same region of the field later (current), decide what to learn.
// The input method (ErgouIME/Speech/CorrectionTracker.swift) reads the
// field and stores the result; nothing here leaves the Mac.
//
// How an edit becomes "heard A → meant B" (design: docs/superpowers/specs/
// 2026-11-11-voice-correction-learning-design.md › 怎么认定是“改了一个词”):
//   1. character diff (LCS) of original and current; a trailing pure
//      insertion after unchanged text is the user typing on and is
//      ignored; after deleted text it replaces that text, up to the end of
//      the first word or Han run ("…用 Orca" → "…用 Swift 然后"), without
//      a trailing - _ . ("Swift." → "Swift"); a Han run longer than 6 is
//      typing, not a word, and is dropped;
//   2. the edits are grouped into spans; a span touching Latin letters or
//      digits grows to whole words (letters, digits, - _ . + #, but no
//      leading or trailing - _ . from the unchanged text), so Orca → rea is
//      one span although the diff saw "O" deleted and "c" → "e";
//   3. spans that overlap or are only spaces apart are merged
//      (SBP API → sub2api);
//   4. a span whose edit turns a term a rule put there back into the
//      rule's heard is a revert and vetoes the rule whatever else changed
//      (short dictations, several edits); everything else (learning, and
//      B → C below) needs the limits: at most 2 spans with both sides
//      non-empty; the changed characters, max(old, new) over all spans, at
//      most half of the original; a span with an empty side (a pure
//      deletion or insertion) never learns;
//   5. a change of exactly one Han character (on both sides) is padded in
//      its run of Han characters to 3 characters, 1 left and 1 right,
//      more on one side when the other runs out (肖 → 效 becomes
//      生肖日 → 生效日, so 生肖 itself is never rewritten); fewer than 3:
//      no rule;
//   6. both sides must pass VoiceTermRules.term; case-only and
//      punctuation-only changes are dropped;
//   7. a span that touches a place where a rule used when typing put its
//      term vetoes the rule, and learns heard → C when the edited term C is
//      a third word (found by position in the original, not by the padded
//      span, so 按效日审批 → 按肖日审批 vetoes 肖日审 → 效日审); otherwise A
//      must look like a name (CommonWords; Latin: a word of ≥ 3 characters
//      that is not common, Han: 2–6, mixed: ≥ 2 non-space characters) to
//      build a rule, else only B is recorded as a hotword when it looks
//      like a name itself (B also at most 6 Han characters).

import Foundation

/// One learned replacement: the recogniser wrote `heard`, the user meant `term`.
struct CorrectionPair: Codable, Equatable, Hashable {
    var heard: String
    var term: String
}

enum CorrectionEvent: Equatable {
    /// Build a replacement rule (and record the term).
    case learn(CorrectionPair)
    /// Record the term only (the heard side failed the guard).
    case hotword(String)
    /// The user undid our replacement.
    case veto(CorrectionPair)
}

enum EditCorrection {
    static let maxSpans = 2
    static let maxHanHeard = 6
    static let hanPadTo = 3
    /// Longer texts are not compared (the diff is quadratic).
    static let maxCompared = 1_000

    /// original = what was typed; current = the same region now (may have
    /// extra trailing text); applied = rules used when typing it.
    static func outcome(original: String, current: String, applied: [CorrectionPair]) -> [CorrectionEvent] {
        guard original != current else { return [] }
        let text = Array(original)
        let ops = withoutTrailingTyping(diff(text, Array(current)))
        let found = spans(ops)
        // Learning and B → C need the limits; a revert does not.
        let learnable = withinLimits(found, originalCount: text.count)
        // Where the rules used when typing put their terms.
        let placed = applied.flatMap { rule in occurrences(of: rule.term, in: text).map { (rule: rule, at: $0) } }

        var events: [CorrectionEvent] = []
        for span in found {
            // Case, spaces or punctuation only: not a correction, not a revert.
            guard normalized(span.old) != normalized(span.new) else { continue }
            let hits = placed.filter { $0.at.overlaps(span.oldRange) }
            if !hits.isEmpty {
                var seen = Set<CorrectionPair>()
                for hit in hits where seen.insert(hit.rule).inserted {
                    // The term as the user left it: the edit applied inside the occurrence.
                    let lo = min(hit.at.lowerBound, span.oldRange.lowerBound)
                    let hi = max(hit.at.upperBound, span.oldRange.upperBound)
                    let edited = String(text[lo..<span.oldRange.lowerBound]) + span.rawNew
                        + String(text[span.oldRange.upperBound..<hi])
                    if normalized(edited) == normalized(hit.rule.heard) {
                        // Changed back to what was heard: always a veto.
                        events.append(.veto(hit.rule))
                    } else if learnable, !span.hasEmptySide {
                        events.append(.veto(hit.rule))
                        if let c = VoiceTermRules.term(edited) {
                            events += classify(heard: hit.rule.heard, term: c, padFailed: false)
                        }
                    }
                }
                continue
            }
            guard learnable, !span.hasEmptySide,
                  let old = VoiceTermRules.term(span.old), let new = VoiceTermRules.term(span.new) else { continue }
            events += classify(heard: old, term: new, padFailed: span.padFailed)
        }
        return events
    }

    /// At most `maxSpans` spans with both sides non-empty, and the changed
    /// characters of all spans at most half of the original.
    static func withinLimits(_ spans: [Span], originalCount: Int) -> Bool {
        guard spans.filter({ !$0.hasEmptySide }).count <= maxSpans else { return false }
        return spans.reduce(0) { $0 + $1.changed } * 2 <= originalCount
    }

    /// Drops what the user typed after the insertion. Inserts at the end
    /// that follow deleted text replace it (the region ended with the
    /// corrected word): those are kept up to the end of the first word or
    /// Han run, so "打开 Orca" → "打开 Swift 然后" keeps "Swift". A word
    /// loses a trailing - _ . ("Swift." keeps "Swift"); a Han run longer
    /// than maxHanHeard is the user typing a phrase and is dropped.
    static func withoutTrailingTyping(_ ops: [Op]) -> [Op] {
        var start = ops.count
        while start > 0, case .insert = ops[start - 1] { start -= 1 }
        guard start < ops.count, start > 0, case .delete = ops[start - 1] else { return Array(ops[..<start]) }
        let inserted = ops[start...].compactMap(\.new)
        let lead = inserted.prefix { $0.isWhitespace }.count
        guard lead < inserted.count else { return Array(ops[..<start]) }
        let kind = charClass(inserted[lead])
        var run = inserted.dropFirst(lead).prefix { charClass($0) == kind }.count
        if kind == .word {
            while run > 0, edgeTrimmed.contains(inserted[lead + run - 1]) { run -= 1 }
        }
        if run == 0 || (kind == .han && run > maxHanHeard) { return Array(ops[..<start]) }
        return Array(ops[..<(start + lead + run)])
    }

    /// Where `term` occurs in `text` (ignoring case). A Latin edge must not
    /// touch a letter or digit (so "Orca." and "x-Orca" match, "Orcanet"
    /// does not). Shared by apply and the revert detection in outcome, so a
    /// term apply wrote is always found again.
    static func occurrences(of term: String, in text: [Character]) -> [Range<Int>] {
        let t = Array(term.lowercased())
        guard !t.isEmpty, t.count <= text.count else { return [] }
        let lower = text.map { Array(String($0).lowercased()).first ?? $0 }
        var found: [Range<Int>] = []
        for i in 0...(text.count - t.count) where Array(lower[i..<(i + t.count)]) == t {
            if isLatinAlphanumeric(t.first!), i > 0, isLatinAlphanumeric(text[i - 1]) { continue }
            if isLatinAlphanumeric(t.last!), i + t.count < text.count, isLatinAlphanumeric(text[i + t.count]) { continue }
            found.append(i..<(i + t.count))
        }
        return found
    }

    // MARK: - Diff

    enum Op: Equatable {
        case match(Character)
        case delete(Character)
        case insert(Character)

        var old: Character? {
            switch self { case .match(let c), .delete(let c): return c; case .insert: return nil }
        }
        var new: Character? {
            switch self { case .match(let c), .insert(let c): return c; case .delete: return nil }
        }
        var isMatch: Bool { if case .match = self { return true }; return false }
    }

    /// Longest-common-subsequence alignment. Matches are taken as early as
    /// possible, so insertions at the end stay at the end.
    static func diff(_ a: [Character], _ b: [Character]) -> [Op] {
        // A common prefix needs no table.
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        let x = Array(a[prefix...]), y = Array(b[prefix...])
        var ops = a[..<prefix].map { Op.match($0) }
        guard x.count <= maxCompared, y.count <= maxCompared else {
            // Too long to align: everything after the prefix changed.
            return ops + x.map { .delete($0) } + y.map { .insert($0) }
        }
        let n = x.count, m = y.count, w = m + 1
        // lcs[i * w + j] = LCS length of x[i...] and y[j...].
        var lcs = [Int32](repeating: 0, count: (n + 1) * w)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i * w + j] = x[i] == y[j] ? lcs[(i + 1) * w + j + 1] + 1
                        : max(lcs[(i + 1) * w + j], lcs[i * w + j + 1])
                }
            }
        }
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, x[i] == y[j] {
                ops.append(.match(x[i])); i += 1; j += 1
            } else if j == m || (i < n && lcs[(i + 1) * w + j] >= lcs[i * w + j + 1]) {
                ops.append(.delete(x[i])); i += 1
            } else {
                ops.append(.insert(y[j])); j += 1
            }
        }
        return ops
    }

    // MARK: - Spans

    struct Span: Equatable {
        /// Both sides, Han-padded, spaces trimmed.
        var old: String
        var new: String
        /// A single Han character that could not be padded to 3.
        var padFailed = false
        /// The edit itself (not padded): its characters in the original,
        /// and what replaced them.
        var oldRange: Range<Int>
        var rawNew: String
        /// max(old, new) characters before padding, for the limits.
        var changed = 0
        /// Old or new is empty or only spaces: a deletion or insertion.
        var hasEmptySide = false
    }

    /// The changed spans after word expansion, merging and Han padding, in
    /// text order. The limits are checked by the caller (withinLimits).
    static func spans(_ ops: [Op]) -> [Span] {
        // 1. Raw spans: runs of non-matching ops, as half-open op ranges.
        var ranges: [Range<Int>] = []
        var k = 0
        while k < ops.count {
            guard !ops[k].isMatch else { k += 1; continue }
            let start = k
            while k < ops.count, !ops[k].isMatch { k += 1 }
            ranges.append(start..<k)
        }
        guard !ranges.isEmpty else { return [] }

        // 2. Latin spans grow to whole words.
        ranges = ranges.map { r in
            // Grow on a side when the change starts / ends with a word character.
            let olds = ops[r].compactMap(\.old), news = ops[r].compactMap(\.new)
            func word(_ c: Character?) -> Bool { c.map(isWordChar) ?? false }
            let growLeft = word(olds.first) || word(news.first), growRight = word(olds.last) || word(news.last)
            var lo = r.lowerBound, hi = r.upperBound
            while growLeft, lo > 0, ops[lo - 1].isMatch, word(ops[lo - 1].old) { lo -= 1 }
            while growRight, hi < ops.count, ops[hi].isMatch, word(ops[hi].old) { hi += 1 }
            // Unchanged - _ . at the edges belong to the sentence ("Orca.").
            while lo < r.lowerBound, ops[lo].isMatch, let c = ops[lo].old, edgeTrimmed.contains(c) { lo += 1 }
            while hi > r.upperBound, ops[hi - 1].isMatch, let c = ops[hi - 1].old, edgeTrimmed.contains(c) { hi -= 1 }
            return lo..<hi
        }

        // 3. Merge spans that overlap, touch, or are only spaces apart.
        var merged: [Range<Int>] = []
        for r in ranges {
            if let last = merged.last,
               r.lowerBound <= last.upperBound
                || ops[last.upperBound..<r.lowerBound].allSatisfy({ $0.isMatch && $0.old == " " }) {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }

        func side(_ r: Range<Int>, _ pick: (Op) -> Character?) -> String { String(ops[r].compactMap(pick)) }

        // Position in the original of each op that has an old character.
        var position: [Int?] = []
        var next = 0
        for op in ops {
            if op.old != nil { position.append(next); next += 1 } else { position.append(nil) }
        }

        // 4. Han padding for a one-character change.
        return merged.map { r in
            let old = side(r, \.old), new = side(r, \.new)
            let inOriginal = r.compactMap { position[$0] }
            // A pure insertion sits between two original characters.
            let at = position[..<r.lowerBound].reversed().first { $0 != nil }.map { $0! + 1 } ?? 0
            let oldRange = inOriginal.first.map { $0..<(inOriginal.last! + 1) } ?? at..<at
            let changed = max(old.count, new.count)
            let empty = trimmed(old).isEmpty || trimmed(new).isEmpty
            guard old.count == 1, new.count == 1, isHan(old.first!), isHan(new.first!) else {
                return Span(old: trimmed(old), new: trimmed(new), oldRange: oldRange, rawNew: new,
                            changed: changed, hasEmptySide: empty)
            }
            // Context is unchanged (match ops), so both sides get the same characters.
            var left = r.lowerBound, right = r.upperBound, length = 1
            func hanMatch(_ i: Int) -> Bool { ops[i].isMatch && isHan(ops[i].old!) }
            if left > 0, hanMatch(left - 1) { left -= 1; length += 1 }
            if right < ops.count, hanMatch(right) { right += 1; length += 1 }
            while length < hanPadTo {
                if right < ops.count, hanMatch(right) { right += 1 } else if left > 0, hanMatch(left - 1) { left -= 1 } else { break }
                length += 1
            }
            return Span(old: side(left..<right, \.old), new: side(left..<right, \.new),
                        padFailed: length < hanPadTo, oldRange: oldRange, rawNew: new,
                        changed: changed, hasEmptySide: false)
        }
    }

    // MARK: - Guard

    /// A rule when `heard` looks like a name, else at most a hotword. A
    /// term with more than maxHanHeard Han characters is a phrase the user
    /// typed, not a word: nothing.
    private static func classify(heard: String, term: String, padFailed: Bool) -> [CorrectionEvent] {
        guard term.filter(isHan).count <= maxHanHeard else { return [] }
        if !padFailed, looksLikeName(heard) {
            return [.learn(CorrectionPair(heard: heard, term: term))]
        }
        return looksLikeName(term) ? [.hotword(term)] : []
    }

    /// Latin: one space-separated word of ≥ 3 characters that is not a
    /// common word ("is a" is not a name); Han: 2–maxHanHeard; mixed: ≥ 2
    /// non-space characters; never a common word as a whole.
    private static func looksLikeName(_ s: String) -> Bool {
        guard !CommonWords.contains(s) else { return false }
        let han = s.filter(isHan).count
        let latin = s.filter(isLatinLetter).count
        if han > 0 && latin > 0 { return s.filter { !$0.isWhitespace }.count >= 2 }
        if han > 0 { return han >= 2 && han <= maxHanHeard }
        return s.split(separator: " ").contains { $0.count >= 3 && !CommonWords.contains(String($0)) }
    }

    // MARK: - Characters

    private static let wordPunctuation: Set<Character> = ["-", "_", ".", "+", "#"]
    private static let edgeTrimmed: Set<Character> = ["-", "_", "."]

    /// Part of a Latin word: letters below the CJK blocks, digits, - _ . + #
    static func isWordChar(_ c: Character) -> Bool {
        isLatinLetter(c) || (c.isNumber && c.unicodeScalars.first!.value < 0x2E80) || wordPunctuation.contains(c)
    }

    static func isLatinAlphanumeric(_ c: Character) -> Bool {
        isLatinLetter(c) || (c.isNumber && c.unicodeScalars.first!.value < 0x2E80)
    }

    static func isLatinLetter(_ c: Character) -> Bool {
        c.isLetter && c.unicodeScalars.first!.value < 0x2E80
    }

    static func isHan(_ c: Character) -> Bool {
        c.unicodeScalars.first!.properties.isIdeographic
    }

    private enum CharClass { case word, han, other }

    private static func charClass(_ c: Character) -> CharClass {
        isWordChar(c) ? .word : isHan(c) ? .han : .other
    }

    private static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }

    /// Letters and digits only, ignoring case: equal means the edit only
    /// changed case, spaces or punctuation.
    private static func normalized(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

// MARK: - Replacement

extension EditCorrection {
    /// Applies learned rules to a new voice result. Longest `heard` first,
    /// then left to right; a match never overlaps an earlier one. A Latin
    /// edge of `heard` must not touch a letter or digit in the text (ignoring case); a Han edge matches as a
    /// substring. The output is the rule's `term`. `applied` lists each
    /// rule once, in the order of its first match in the text.
    static func apply(_ text: String, rules: [CorrectionPair]) -> (text: String, applied: [CorrectionPair]) {
        let chars = Array(text)
        var candidates: [(rule: CorrectionPair, range: Range<Int>, index: Int)] = []
        for (index, rule) in rules.enumerated() {
            candidates += occurrences(of: rule.heard, in: chars).map { (rule: rule, range: $0, index: index) }
        }
        // Longest first, then leftmost, then rule order: deterministic.
        candidates.sort {
            if $0.range.count != $1.range.count { return $0.range.count > $1.range.count }
            if $0.range.lowerBound != $1.range.lowerBound { return $0.range.lowerBound < $1.range.lowerBound }
            return $0.index < $1.index
        }
        var taken: [(rule: CorrectionPair, range: Range<Int>)] = []
        for c in candidates where !taken.contains(where: { $0.range.overlaps(c.range) }) {
            taken.append((c.rule, c.range))
        }
        taken.sort { $0.range.lowerBound < $1.range.lowerBound }

        var out = ""
        var applied: [CorrectionPair] = []
        var cursor = 0
        for m in taken {
            out += String(chars[cursor..<m.range.lowerBound]) + m.rule.term
            cursor = m.range.upperBound
            if !applied.contains(m.rule) { applied.append(m.rule) }
        }
        out += String(chars[cursor...])
        return (out, applied)
    }
}
