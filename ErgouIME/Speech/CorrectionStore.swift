// ergou-ime — the replacement rules learned from the user's edits.
// SPDX-License-Identifier: GPL-3.0-only
//
// "heard A → meant B" pairs (EditCorrection). They live in the input
// method's PRIVATE container (Paths.privateRoot), never in the App Group
// container: Settings has network access and can write there, and a rule
// rewrites the text the user dictates. The file is still re-validated on
// every read. Nothing here is logged except counts. Main thread only.

import Foundation

final class CorrectionStore {
    static let shared = CorrectionStore(file: Paths.privateRoot.appendingPathComponent("voice-corrections.json"))

    static let maxRules = 300
    static let maxVetoes = 300

    private struct Rule: Codable, Equatable {
        var heard: String
        var term: String
        var learned: Date
        var lastUsed: Date
    }

    private struct Veto: Codable, Equatable {
        var heard: String
        var term: String
    }

    private struct FileContents: Codable {
        var version = 1
        var rules: [Rule] = []
        var vetoed: [Veto] = []
    }

    private let file: URL
    /// Most recently used first.
    private var stored = FileContents()
    private var lastStamp = Date.distantPast

    init(file: URL) {
        self.file = file
        load()
    }

    /// Most recently used first.
    var rules: [CorrectionPair] { stored.rules.map { CorrectionPair(heard: $0.heard, term: $0.term) } }

    /// Ignored when the pair is invalid or was vetoed. A rule with the same
    /// `heard` (any case) is replaced.
    func learn(_ pair: CorrectionPair) {
        guard let p = Self.valid(pair), !isVetoed(p) else { return }
        let now = stamp()
        stored.rules.removeAll { Self.same($0.heard, p.heard) }
        stored.rules.insert(Rule(heard: p.heard, term: p.term, learned: now, lastUsed: now), at: 0)
        if stored.rules.count > Self.maxRules { stored.rules = Array(stored.rules.prefix(Self.maxRules)) }
        save()
    }

    /// Removes the rule and remembers that the user does not want it.
    func veto(_ pair: CorrectionPair) {
        guard let p = Self.valid(pair) else { return }
        stored.rules.removeAll { Self.same($0.heard, p.heard) && Self.same($0.term, p.term) }
        if !isVetoed(p) {
            stored.vetoed.append(Veto(heard: p.heard, term: p.term))
            if stored.vetoed.count > Self.maxVetoes { stored.vetoed.removeFirst(stored.vetoed.count - Self.maxVetoes) }
        }
        save()
    }

    /// Bump `lastUsed` after a replacement.
    func used(_ pairs: [CorrectionPair]) {
        var changed = false
        let now = stamp()
        for p in pairs {
            guard let i = stored.rules.firstIndex(where: { Self.same($0.heard, p.heard) && Self.same($0.term, p.term) }) else { continue }
            var rule = stored.rules.remove(at: i)
            rule.lastUsed = now
            stored.rules.insert(rule, at: 0)
            changed = true
        }
        if changed { save() }
    }

    /// The term was deleted in 我的词: its rules go too.
    func removeRules(forTerm term: String) {
        let before = stored.rules.count
        stored.rules.removeAll { Self.same($0.term, term) }
        if stored.rules.count != before { save() }
    }

    // MARK: - Internals

    private func isVetoed(_ p: CorrectionPair) -> Bool {
        stored.vetoed.contains { Self.same($0.heard, p.heard) && Self.same($0.term, p.term) }
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive]) == .orderedSame
    }

    /// Both sides pass the term rules and still differ ignoring case.
    private static func valid(_ pair: CorrectionPair) -> CorrectionPair? {
        guard let h = VoiceTermRules.term(pair.heard), let t = VoiceTermRules.term(pair.term),
              !same(h, t) else { return nil }
        return CorrectionPair(heard: h, term: t)
    }

    /// Strictly increasing, so ordering survives calls within one tick.
    private func stamp() -> Date {
        let now = max(Date(), lastStamp.addingTimeInterval(0.000_001))
        lastStamp = now
        return now
    }

    private func load() {
        guard let data = SafeFile.read(file, maxBytes: 1 << 20),
              let raw = try? JSONDecoder().decode(FileContents.self, from: data), raw.version == 1 else { return }
        var out = FileContents()
        for r in raw.rules.sorted(by: { $0.lastUsed > $1.lastUsed }) {
            guard let p = Self.valid(CorrectionPair(heard: r.heard, term: r.term)),
                  !out.rules.contains(where: { Self.same($0.heard, p.heard) }) else { continue }
            out.rules.append(Rule(heard: p.heard, term: p.term, learned: r.learned, lastUsed: r.lastUsed))
        }
        out.rules = Array(out.rules.prefix(Self.maxRules))
        for v in raw.vetoed {
            guard let p = Self.valid(CorrectionPair(heard: v.heard, term: v.term)) else { continue }
            out.vetoed.append(Veto(heard: p.heard, term: p.term))
        }
        if out.vetoed.count > Self.maxVetoes { out.vetoed.removeFirst(out.vetoed.count - Self.maxVetoes) }
        stored = out
        lastStamp = out.rules.first?.lastUsed ?? .distantPast
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        guard let data = try? encoder.encode(stored) else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            Log.speech.error("Could not save voice corrections")
        }
    }
}
