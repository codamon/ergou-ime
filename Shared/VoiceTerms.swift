// ergou-ime — 我的词: terms the recogniser should prefer (hotwords).
// SPDX-License-Identifier: GPL-3.0-only
//
// Two sources (D, 2026-11-10):
//   - manual: typed in ErgouIME Settings › 我的词, stored in the shared
//     defaults (SettingKey.voiceTermsManual);
//   - learned: recorded by the input method (TermStore.record), later fed by
//     the tidy-up step when it corrects a misheard name. Stored by the input
//     method in the App Group container (Paths.learnedTerms) so that
//     Settings can show them. Settings never writes that file: 删除 / 固定
//     go through an edit list in the shared defaults plus a Darwin
//     notification, and the input method applies them.
//
// Both programs can write the shared defaults and the App Group container,
// and Settings has network access, so everything read from there is
// untrusted: terms are re-validated on every read (VoiceTermRules.term).
// The terms end up inside the recogniser's prompt; the character whitelist
// keeps out its separators (",") and chat-template syntax ("<|…|>").
//
// Which terms are used (VoiceTermRules.effective):
//   - manual and pinned terms always;
//   - a learned term once it was heard wrong at least once (it has a
//     `heard` variant), otherwise after it was recorded twice;
//   - ordered by count × recency (half-life 30 days), at most 100 terms and
//     about 200 prompt tokens (each term makes every segment slower; 107
//     terms took 271 tokens and doubled the decoding time, D's Mac
//     2026-11-10).
// Nothing here leaves the Mac (Privacy rule 10).

import Foundation

enum TermSource: String, Codable, CaseIterable {
    /// 自动整理 (local) corrected the recogniser.
    case tidy
    /// The cloud tidy-up named it (CloudTidy.Term).
    case cloud
    /// 用户在输入框里改出来的。
    case edit
    /// Anything else the input method learns from in future.
    case other
}

struct LearnedTerm: Codable, Equatable, Identifiable {
    var id: String { term }
    var term: String
    /// What the recogniser wrote instead (most recent first, at most 5).
    var heard: [String] = []
    var count: Int = 0
    var firstSeen: Date
    var lastSeen: Date
    var pinned = false
    var source: TermSource = .tidy
}

/// The learned-terms file (Paths.learnedTerms).
struct LearnedTermsFile: Codable, Equatable {
    var version = 1
    var terms: [LearnedTerm] = []
    /// Deleted in Settings: not learned again (most recent first).
    var dismissed: [String] = []
}

/// A change Settings asks the input method to make to the learned terms.
struct TermEdit: Equatable {
    enum Action: String { case pin, unpin, delete }
    let action: Action
    let term: String

    /// "<action>\t<term>" in SettingKey.voiceTermEdits.
    var stored: String { action.rawValue + "\t" + term }

    init(_ action: Action, _ term: String) { self.action = action; self.term = term }

    init?(stored: String) {
        let parts = stored.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let action = Action(rawValue: String(parts[0])),
              let term = VoiceTermRules.term(String(parts[1])) else { return nil }
        self.init(action, term)
    }
}

enum VoiceTermRules {
    static let maxLength = 24
    static let maxManual = 300
    static let maxLearned = 500
    static let maxDismissed = 300
    static let maxHeard = 5
    static let maxEdits = 200
    /// Terms passed to the recogniser.
    static let maxActive = 100
    /// Estimated prompt tokens for all active terms together (see top).
    static let maxPromptTokens = 200
    static let halfLifeDays = 30.0

    /// Letters of any script, digits, combining marks, spaces and - . + # ' ’ · & _
    private static let extraAllowed = Set("-.+#'’·&_ ".unicodeScalars)

    /// The cleaned term, or nil when it is not allowed: 1–24 characters;
    /// at least one letter (so no pure numbers); nothing that looks like an
    /// e-mail address, a web address, or a password / code / key.
    static func term(_ raw: String) -> String? {
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard (1...maxLength).contains(collapsed.count),
              collapsed.unicodeScalars.allSatisfy(isAllowed),
              collapsed.unicodeScalars.contains(where: { $0.properties.isAlphabetic }),
              !looksLikeWebAddress(collapsed),
              !looksLikeSecret(collapsed)
        else { return nil }
        return collapsed
    }

    private static func isAllowed(_ s: Unicode.Scalar) -> Bool {
        if extraAllowed.contains(s) { return true }
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .nonspacingMark, .spacingMark:
            return true
        default:
            return false
        }
    }

    /// "@" and "/" are not allowed at all; this catches "www.x" and
    /// "example.com" (a dotted name ending in a common top-level domain).
    private static func looksLikeWebAddress(_ s: String) -> Bool {
        let lower = s.lowercased()
        if lower.hasPrefix("www.") { return true }
        let labels = lower.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty && !$0.contains(" ") }) else { return false }
        let tlds: Set<Substring> = ["com", "net", "org", "nz", "au", "cn", "io", "co", "ai", "app", "dev",
                                    "me", "uk", "us", "info", "biz", "top", "xyz", "cc", "tv", "hk", "tw", "jp"]
        return tlds.contains(labels.last!)
    }

    /// Same idea as VoiceHistory.isSensitive: 6+ digits in all, a word like
    /// 密码 / 验证码, or an 8+ character run mixing letters and digits (keys,
    /// generated passwords).
    /// Words that announce a secret ("验证码 4821", "我的密码abc").
    private static let secretWords = ["密码", "验证码", "校验码", "动态码", "口令", "password", "passcode", "passwd"]

    private static func looksLikeSecret(_ s: String) -> Bool {
        let lower = s.lowercased()
        if secretWords.contains(where: lower.contains) { return true }
        // Six digits in all: a phone number split by spaces ("电话021 123 4567").
        if s.filter({ $0.isASCII && $0.isNumber }).count >= 6 { return true }
        let runs = s.split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) })
        for run in runs {
            let digits = run.filter(\.isNumber).count
            let letters = run.filter(\.isLetter).count
            if digits >= 6 && letters == 0 { return true }
            if run.count >= 8 && digits >= 2 && letters >= 2 { return true }
        }
        return false
    }

    static func key(_ term: String) -> String { term.lowercased() }

    /// Valid, de-duplicated (ignoring case, first wins), at most `limit`.
    static func cleaned(_ raw: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in raw {
            guard out.count < limit else { break }
            if let t = term(r), seen.insert(key(t)).inserted { out.append(t) }
        }
        return out
    }

    /// Manual terms as stored in the shared defaults (untrusted).
    static func manual(_ raw: Any?) -> [String] {
        guard let list = raw as? [String] else { return [] }
        return cleaned(Array(list.prefix(maxManual * 2)), limit: maxManual)
    }

    /// The learned-terms file as read from the App Group container
    /// (untrusted): invalid entries are dropped, numbers clamped.
    static func sanitized(_ file: LearnedTermsFile) -> LearnedTermsFile {
        var seen = Set<String>()
        var terms: [LearnedTerm] = []
        for var t in file.terms.prefix(maxLearned * 2) {
            guard terms.count < maxLearned, let clean = term(t.term), seen.insert(key(clean)).inserted else { continue }
            t.term = clean
            t.heard = cleaned(t.heard, limit: maxHeard).filter { key($0) != key(clean) }
            t.count = min(max(t.count, 0), 1_000_000)
            terms.append(t)
        }
        return LearnedTermsFile(version: 1, terms: terms,
                                dismissed: cleaned(file.dismissed, limit: maxDismissed))
    }

    static func decodeFile(_ data: Data) -> LearnedTermsFile {
        guard data.count < 4 << 20 else { return LearnedTermsFile() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(LearnedTermsFile.self, from: data) else { return LearnedTermsFile() }
        return sanitized(file)
    }

    static func encodeFile(_ file: LearnedTermsFile) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(file)
    }

    static func edits(_ raw: Any?) -> [TermEdit] {
        guard let list = raw as? [String] else { return [] }
        return list.prefix(maxEdits).compactMap(TermEdit.init(stored:))
    }

    /// The edit list after the input method applied `applied`, given the
    /// list `now` as it is in the defaults again. Settings appends and keeps
    /// the last maxEdits, so the oldest of ours may have been pushed out:
    /// drop the longest tail of `applied` that `now` starts with. Nothing
    /// matching: keep `now` (applying an edit again is harmless).
    static func editsLeft(now: [String], applied: [String]) -> [String] {
        let pushedOut = (0...applied.count).first { now.starts(with: applied.dropFirst($0)) } ?? applied.count
        return Array(now.dropFirst(applied.count - pushedOut))
    }

    /// A learned term counts once it was heard wrong, or seen twice.
    static func isActive(_ t: LearnedTerm) -> Bool {
        t.pinned || (!t.heard.isEmpty && t.count >= 1) || t.count >= 2
    }

    static func score(_ t: LearnedTerm, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(t.lastSeen) / 86_400)
        return Double(t.count) * pow(0.5, days / halfLifeDays)
    }

    /// Rough Qwen tokenizer cost of a term in the prompt (measured: 107
    /// mostly-English terms, 720 characters → 271 tokens).
    static func promptTokens(_ term: String) -> Int {
        var cjk = 0, other = 0
        for s in term.unicodeScalars { if s.value >= 0x2E80 { cjk += 1 } else { other += 1 } }
        return 1 + Int((Double(cjk) * 0.8 + Double(other) * 0.4).rounded(.up))
    }

    /// The terms handed to the recogniser, in priority order: manual (as
    /// the user ordered them), pinned, then active learned terms by score.
    static func effective(manual: [String], learned: [LearnedTerm], now: Date = Date()) -> [String] {
        let pinned = learned.filter(\.pinned).sorted { score($0, now: now) > score($1, now: now) }
        let rest = learned.filter { !$0.pinned && isActive($0) }
            .sorted { (score($0, now: now), $0.lastSeen) > (score($1, now: now), $1.lastSeen) }
        var seen = Set<String>()
        var out: [String] = []
        var tokens = 0
        for t in manual + pinned.map(\.term) + rest.map(\.term) {
            guard out.count < maxActive else { break }
            guard let clean = term(t), seen.insert(key(clean)).inserted else { continue }
            let cost = promptTokens(clean)
            if tokens + cost > maxPromptTokens { continue }
            tokens += cost
            out.append(clean)
        }
        return out
    }

    /// sherpa-onnx's Qwen3-ASR hotwords option: ASCII commas between terms.
    static func hotwordString(_ terms: [String]) -> String { terms.joined(separator: ",") }

    /// Applies one recording of `term` (heard as `heard`) to the file.
    /// Returns false when nothing changed (invalid, or deleted by the user).
    @discardableResult
    static func record(_ file: inout LearnedTermsFile, term raw: String, heard rawHeard: String?,
                       source: TermSource, now: Date = Date()) -> Bool {
        guard let t = term(raw), !file.dismissed.contains(where: { key($0) == key(t) }) else { return false }
        let heard = rawHeard.flatMap { term($0) }.flatMap { key($0) == key(t) ? nil : $0 }
        if let i = file.terms.firstIndex(where: { key($0.term) == key(t) }) {
            file.terms[i].count += 1
            file.terms[i].lastSeen = now
            if let heard {
                file.terms[i].heard.removeAll { key($0) == key(heard) }
                file.terms[i].heard.insert(heard, at: 0)
                file.terms[i].heard = Array(file.terms[i].heard.prefix(maxHeard))
            }
        } else {
            file.terms.append(LearnedTerm(term: t, heard: heard.map { [$0] } ?? [], count: 1,
                                          firstSeen: now, lastSeen: now, source: source))
        }
        if file.terms.count > maxLearned {
            // Drop the weakest unpinned term.
            let victims = file.terms.indices.filter { !file.terms[$0].pinned }
            if let worst = victims.min(by: { score(file.terms[$0], now: now) < score(file.terms[$1], now: now) }) {
                file.terms.remove(at: worst)
            }
        }
        return true
    }

    /// Applies Settings' 删除 / 固定 requests.
    static func apply(_ edits: [TermEdit], to file: inout LearnedTermsFile) {
        for e in edits {
            let k = key(e.term)
            switch e.action {
            case .pin, .unpin:
                if let i = file.terms.firstIndex(where: { key($0.term) == k }) { file.terms[i].pinned = e.action == .pin }
            case .delete:
                file.terms.removeAll { key($0.term) == k }
                file.dismissed.removeAll { key($0) == k }
                file.dismissed.insert(e.term, at: 0)
                file.dismissed = Array(file.dismissed.prefix(maxDismissed))
            }
        }
    }
}

extension SettingKey {
    /// [String], terms typed in Settings › 我的词 (VoiceTermRules.term).
    static let voiceTermsManual = "voiceTermsManual"
    /// [String], TermEdit.stored lines waiting for the input method.
    static let voiceTermEdits = "voiceTermEdits"
}

extension SharedNotifications {
    /// Settings changed 我的词 (manual list or edit requests).
    static let voiceTermsChanged = "com.codamon.ergou.voice-terms-changed"
}

extension Paths {
    /// Written by the input method only; Settings reads it.
    static var learnedTerms: URL { root.appendingPathComponent("Terms", isDirectory: true)
        .appendingPathComponent("learned-terms.json") }
}

extension SharedSettings {
    static var voiceTermsManual: [String] {
        VoiceTermRules.manual(Paths.sharedDefaults.object(forKey: SettingKey.voiceTermsManual))
    }

    static func saveVoiceTermsManual(_ terms: [String]) {
        Paths.sharedDefaults.set(VoiceTermRules.cleaned(terms, limit: VoiceTermRules.maxManual),
                                 forKey: SettingKey.voiceTermsManual)
    }

    /// Settings: ask the input method to change a learned term.
    static func requestTermEdit(_ edit: TermEdit) {
        var list = Paths.sharedDefaults.stringArray(forKey: SettingKey.voiceTermEdits) ?? []
        list.append(edit.stored)
        Paths.sharedDefaults.set(Array(list.suffix(VoiceTermRules.maxEdits)), forKey: SettingKey.voiceTermEdits)
    }

    static var pendingTermEdits: [TermEdit] {
        VoiceTermRules.edits(Paths.sharedDefaults.object(forKey: SettingKey.voiceTermEdits))
    }

    /// Settings: the learned terms as the input method last saved them,
    /// with requests it has not applied yet already applied.
    static var learnedTermsForDisplay: LearnedTermsFile {
        var file = (try? Data(contentsOf: Paths.learnedTerms)).map(VoiceTermRules.decodeFile) ?? LearnedTermsFile()
        VoiceTermRules.apply(pendingTermEdits, to: &file)
        return file
    }
}
