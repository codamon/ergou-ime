// ergou-ime — tests for CorrectionStore (ErgouIME/Speech/CorrectionStore.swift).
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

private func pair(_ heard: String, _ term: String) -> CorrectionPair { CorrectionPair(heard: heard, term: term) }

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ergou-cs-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("voice-corrections.json")
}

private func learnTwice(_ s: CorrectionStore, _ p: CorrectionPair) { s.learn(p); s.learn(p) }

private func cleanup(_ file: URL) { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

let correctionStoreTests: [Test] = [
    ("learnPersists", {
        let f = tempFile(); defer { cleanup(f) }
        learnTwice(CorrectionStore(file: f), pair("Orca", "rea"))
        expect(CorrectionStore(file: f).rules, [pair("Orca", "rea")], "persisted")
    }),
    ("vetoBlocksRelearn", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        learnTwice(s, pair("Orca", "rea"))
        s.veto(pair("Orca", "rea"))
        expect(s.rules, [], "veto removes the rule")
        s.learn(pair("orca", "REA"))
        expect(s.rules, [], "vetoed pair ignored (case-insensitive)")
        expect(CorrectionStore(file: f).rules, [], "veto persisted")
    }),
    ("sameHeardReplaces", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        learnTwice(s, pair("Orca", "rea"))
        learnTwice(s, pair("orca", "REA"))
        expect(s.rules, [pair("orca", "REA")], "same pair merges, latest spelling")
        expect(s.rules.count, 1, "one rule")
    }),
    ("capDropsLeastRecentlyUsed", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        func name(_ i: Int) -> String { String(UnicodeScalar(UInt8(97 + i / 26))) + String(UnicodeScalar(UInt8(97 + i % 26))) }
        for i in 0..<301 { learnTwice(s, pair("heard " + name(i), "term " + name(i))) }
        expect(s.rules.count, 300, "capped")
        check(!s.rules.contains(pair("heard " + name(0), "term " + name(0))), "oldest dropped")
        expect(s.rules.first, pair("heard " + name(300), "term " + name(300)), "newest first")
    }),
    ("usedBumpsRecency", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        learnTwice(s, pair("aaa", "alpha")); learnTwice(s, pair("bbb", "beta"))
        s.used([pair("aaa", "alpha")])
        expect(s.rules.first, pair("aaa", "alpha"), "bumped to front")
    }),
    ("removeRulesForTerm", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        learnTwice(s, pair("Orca", "rea")); learnTwice(s, pair("Rhea", "REA")); learnTwice(s, pair("Foo", "bar"))
        s.removeRules(forTerm: " Rea ")
        expect(s.rules, [pair("Foo", "bar")], "case-insensitive term removal")
        expect(CorrectionStore(file: f).rules, [pair("Foo", "bar")], "persisted")
    }),
    ("invalidPairsRejected", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        s.learn(pair("Orca", "orca"))
        s.learn(pair("a,b", "rea"))
        expect(s.rules, [], "same-ignoring-case and invalid rejected")
    }),
    ("corruptFileIgnored", {
        let f = tempFile(); defer { cleanup(f) }
        try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("not json {{".utf8).write(to: f)
        let s = CorrectionStore(file: f)
        expect(s.rules, [], "empty")
        learnTwice(s, pair("Orca", "rea"))
        expect(CorrectionStore(file: f).rules, [pair("Orca", "rea")], "recovers")
    }),
    ("oversizedFileIgnored", {
        let f = tempFile(); defer { cleanup(f) }
        try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(count: (1 << 20) + 10).write(to: f)
        expect(CorrectionStore(file: f).rules, [], "empty")
    }),
    ("firstSightingIsPending", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        s.learn(pair("Orca", "rea"))
        expect(s.rules, [], "one sighting does not replace")
    }),
    ("secondSightingActivates", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        s.learn(pair("Orca", "rea")); s.learn(pair("orca", "REA"))
        expect(s.rules.count, 1, "active after two")
    }),
    ("differentTermResetsCount", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        s.learn(pair("Orca", "rea"))
        s.learn(pair("Orca", "Rhea"))
        expect(s.rules, [], "new term starts again")
        s.learn(pair("Orca", "Rhea"))
        expect(s.rules, [pair("Orca", "Rhea")], "second sighting of the new term")
    }),
    ("countPersists", {
        let f = tempFile(); defer { cleanup(f) }
        CorrectionStore(file: f).learn(pair("Orca", "rea"))
        let s = CorrectionStore(file: f)
        expect(s.rules, [], "still pending")
        s.learn(pair("Orca", "rea"))
        expect(s.rules, [pair("Orca", "rea")], "active after reload")
    }),
    ("pendingCountsTowardCap", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        func name(_ i: Int) -> String { String(UnicodeScalar(UInt8(97 + i / 26))) + String(UnicodeScalar(UInt8(97 + i % 26))) }
        learnTwice(s, pair("heard " + name(0), "term " + name(0)))
        for i in 1...300 { s.learn(pair("heard " + name(i), "term " + name(i))) }
        expect(s.rules, [], "the oldest (active) rule was dropped as least recent")
    }),
    ("relearnKeepsLearnedDate", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        learnTwice(s, pair("Orca", "rea"))
        let first = (try? String(contentsOf: f, encoding: .utf8)) ?? ""
        s.learn(pair("Orca", "rea"))
        let after = (try? String(contentsOf: f, encoding: .utf8)) ?? ""
        func learnedValue(_ t: String) -> String {
            guard let r = t.range(of: "\"learned\":") else { return "" }
            return String(t[r.upperBound...].prefix { $0 != "," && $0 != "}" })
        }
        check(!learnedValue(first).isEmpty, "learned present")
        expect(learnedValue(after), learnedValue(first), "learned date kept")
    }),
    ("voteCapHolds", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        func name(_ i: Int) -> String { String(UnicodeScalar(UInt8(97 + i / 26))) + String(UnicodeScalar(UInt8(97 + i % 26))) }
        for i in 0..<310 { s.veto(pair("heard " + name(i), "term " + name(i))) }
        s.learn(pair("heard " + name(0), "term " + name(0))); s.learn(pair("heard " + name(0), "term " + name(0)))
        expect(s.rules.count, 1, "oldest veto dropped, learnable again")
        s.learn(pair("heard " + name(309), "term " + name(309))); s.learn(pair("heard " + name(309), "term " + name(309)))
        expect(s.rules.count, 1, "newest veto still blocks")
    }),
]
