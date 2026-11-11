// ergou-ime — tests for CorrectionStore (ErgouIME/Speech/CorrectionStore.swift).
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

private func pair(_ heard: String, _ term: String) -> CorrectionPair { CorrectionPair(heard: heard, term: term) }

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ergou-cs-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("voice-corrections.json")
}

private func cleanup(_ file: URL) { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

let correctionStoreTests: [Test] = [
    ("learnPersists", {
        let f = tempFile(); defer { cleanup(f) }
        CorrectionStore(file: f).learn(pair("Orca", "rea"))
        expect(CorrectionStore(file: f).rules, [pair("Orca", "rea")], "persisted")
    }),
    ("vetoBlocksRelearn", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        s.learn(pair("Orca", "rea"))
        s.veto(pair("Orca", "rea"))
        expect(s.rules, [], "veto removes the rule")
        s.learn(pair("orca", "REA"))
        expect(s.rules, [], "vetoed pair ignored (case-insensitive)")
        expect(CorrectionStore(file: f).rules, [], "veto persisted")
    }),
    ("sameHeardReplaces", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        s.learn(pair("Orca", "rea"))
        s.learn(pair("orca", "REA"))
        expect(s.rules, [pair("orca", "REA")], "replaced")
    }),
    ("capDropsLeastRecentlyUsed", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        func name(_ i: Int) -> String { String(UnicodeScalar(UInt8(97 + i / 26))) + String(UnicodeScalar(UInt8(97 + i % 26))) }
        for i in 0..<301 { s.learn(pair("heard " + name(i), "term " + name(i))) }
        expect(s.rules.count, 300, "capped")
        check(!s.rules.contains(pair("heard " + name(0), "term " + name(0))), "oldest dropped")
        expect(s.rules.first, pair("heard " + name(300), "term " + name(300)), "newest first")
    }),
    ("usedBumpsRecency", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        s.learn(pair("aaa", "alpha")); s.learn(pair("bbb", "beta"))
        s.used([pair("aaa", "alpha")])
        expect(s.rules.first, pair("aaa", "alpha"), "bumped to front")
    }),
    ("removeRulesForTerm", {
        let f = tempFile(); defer { cleanup(f) }
        let s = CorrectionStore(file: f)
        s.learn(pair("Orca", "rea")); s.learn(pair("Rhea", "REA")); s.learn(pair("Foo", "bar"))
        s.removeRules(forTerm: "Rea")
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
        s.learn(pair("Orca", "rea"))
        expect(CorrectionStore(file: f).rules, [pair("Orca", "rea")], "recovers")
    }),
    ("oversizedFileIgnored", {
        let f = tempFile(); defer { cleanup(f) }
        try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(count: (1 << 20) + 10).write(to: f)
        expect(CorrectionStore(file: f).rules, [], "empty")
    }),
]
