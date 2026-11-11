// ergou-ime — tests for the wiring around the stores: CorrectionRouting
// (ErgouIME/Speech/CorrectionRouting.swift), TermStore.record /
// cloudTerms (ErgouIME/Speech/TermStore.swift, Shared/VoiceTerms.swift).
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

private func pair(_ heard: String, _ term: String) -> CorrectionPair { CorrectionPair(heard: heard, term: term) }

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ergou-cw-\(UUID().uuidString)", isDirectory: true)
}

/// A TermStore and a CorrectionStore on temporary files, wired like the
/// input method (onTermDeleted → removeRules).
private final class Stores {
    let dir = tempDir()
    let suite = "ergou-tests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let terms: TermStore
    let rules: CorrectionStore
    var deleted: [String] = []

    init() {
        defaults = UserDefaults(suiteName: suite)!
        terms = TermStore(file: dir.appendingPathComponent("learned-terms.json"), defaults: defaults)
        terms.isSecureInput = { false }
        rules = CorrectionStore(file: dir.appendingPathComponent("voice-corrections.json"))
        terms.onTermDeleted = { [unowned self] in self.deleted.append($0); self.rules.removeRules(forTerm: $0) }
    }

    func handle(_ events: [CorrectionEvent]) -> (learned: Int, vetoed: Int) {
        CorrectionRouting.route(events,
                                recordTerm: { self.terms.record(term: $0, heard: $1, source: .edit) },
                                learn: { self.rules.learn($0) },
                                veto: { self.rules.veto($0) })
    }

    /// Settings' 删除 for `term`, as the input method sees it.
    func deleteInSettings(_ term: String) {
        defaults.set([TermEdit(.delete, term).stored], forKey: SettingKey.voiceTermEdits)
        terms.settingsChanged()
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suite)
    }
}

let correctionWiringTests: [Test] = [
    ("routeLearnsOnlyWhenTermRecorded", {
        var learned: [CorrectionPair] = [], vetoed: [CorrectionPair] = [], recorded: [String] = []
        let events: [CorrectionEvent] = [.learn(pair("Orca", "rea")), .learn(pair("Rhia", "Rhea")),
                                         .hotword("Swift"), .veto(pair("SBP", "sub2api"))]
        let counts = CorrectionRouting.route(events,
                                             recordTerm: { term, _ in recorded.append(term); return term != "Rhea" },
                                             learn: { learned.append($0) }, veto: { vetoed.append($0) })
        expect(recorded, ["rea", "Rhea", "Swift"], "every term goes to 我的词 first")
        expect(learned, [pair("Orca", "rea")], "no rule when 我的词 refused the term")
        expect(vetoed, [pair("SBP", "sub2api")], "veto")
        expect(counts.learned, 2, "learned count")
        expect(counts.vetoed, 1, "vetoed count")
    }),
    ("deletedTermLearnsNoRule", {
        let s = Stores(); defer { s.cleanup() }
        let event = CorrectionEvent.learn(pair("Orca", "rea"))
        _ = s.handle([event])
        s.deleteInSettings("rea")
        check(!s.terms.learnedTerms.contains { $0.term == "rea" }, "deleted from 我的词")
        _ = s.handle([event]); _ = s.handle([event])
        expect(s.rules.rules, [], "a dismissed term never becomes a rule")
        check(!s.terms.learnedTerms.contains { $0.term == "rea" }, "and stays deleted")
    }),
    ("recordReturnsWhetherRecorded", {
        let s = Stores(); defer { s.cleanup() }
        check(s.terms.record(term: "Orca", heard: nil, source: .edit), "new term")
        check(!s.terms.record(term: "a,b", heard: nil, source: .edit), "invalid term")
        s.terms.isSecureInput = { true }
        check(!s.terms.record(term: "Swift", heard: nil, source: .edit), "secure input")
    }),
    ("evictionIsReported", {
        let s = Stores(); defer { s.cleanup() }
        // Letters only (letters and digits can look like a secret).
        func name(_ i: Int) -> String { "word" + String(UnicodeScalar(UInt8(97 + i / 26))) + String(UnicodeScalar(UInt8(97 + i % 26))) }
        for i in 0..<VoiceTermRules.maxLearned { s.terms.record(term: name(i), heard: nil, source: .edit) }
        expect(s.deleted, [], "no eviction up to the cap")
        let ok = s.terms.record(term: "Orca", heard: "Orka", source: .edit)
        expect(s.terms.learnedTerms.count, VoiceTermRules.maxLearned, "capped")
        expect(s.deleted.count, 1, "evicted term reported")
        if let gone = s.deleted.first {
            check(!s.terms.learnedTerms.contains { $0.term == gone }, "reported term is the one dropped")
            expect(ok, gone != "Orca", "true unless the new term itself was dropped")
        }
    }),
    ("cloudTermsSkipEditLearned", {
        let now = Date()
        func t(_ term: String, _ source: TermSource) -> LearnedTerm {
            LearnedTerm(term: term, heard: [], count: 2, firstSeen: now, lastSeen: now, source: source)
        }
        let learned = [t("rea", .edit), t("Swift", .edit), t("基督城", .cloud)]
        expect(VoiceTermRules.cloudTerms(["Orca", "REA", "Swift", "基督城"], manual: ["swift"], learned: learned),
               ["Orca", "Swift", "基督城"], "edit-learned terms stay local unless typed in Settings")
    }),
    ("termStoreCloudTerms", {
        let s = Stores(); defer { s.cleanup() }
        s.terms.record(term: "基督城", heard: "鸡肚城", source: .cloud)
        s.terms.record(term: "rea", heard: "Orca", source: .edit)
        check(s.terms.activeTerms.contains("rea"), "edit-learned term is a local hotword")
        check(s.terms.activeTerms.contains("基督城"), "cloud term active")
        expect(s.terms.cloudTerms, s.terms.activeTerms.filter { $0 != "rea" }, "not sent to the cloud")
    }),
    ("prepareAutoSpaceAroundRules", {
        let mixed = pair("B 中", "币种")   // learned from spaced field text
        let r = CorrectionRouting.prepare("B中也是USD", rules: [mixed], autoSpace: true)
        expect(r.text, "币种也是 USD", "spaced before the rules")
        expect(r.applied, [mixed], "")
        expect(CorrectionRouting.prepare("看生肖日吧", rules: [pair("生肖日", "Orca")], autoSpace: true).text,
               "看 Orca 吧", "and the replaced term spaced after")
        let off = CorrectionRouting.prepare("B中也是USD", rules: [mixed], autoSpace: false)
        expect(off.text, "B中也是USD", "AutoSpace off: text as recognised")
        expect(off.applied, [], "")
    }),
]
