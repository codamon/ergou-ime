// ergou-ime — 从我的修改里学习: the pure steps around the stores.
// SPDX-License-Identifier: GPL-3.0-only
//
// Kept apart from CorrectionLearning (AppKit, InputMethodKit, SecureInput)
// so tests/swift can run them: where each CorrectionEvent goes, and the
// order of replacement and AutoSpace when a voice result is typed.

import Foundation

enum CorrectionRouting {
    /// Sends events to the stores. A rule is learned only when its term is
    /// in 我的词 (`recordTerm` returned true): not when the user deleted the
    /// term earlier, not when it was evicted right away.
    @discardableResult
    static func route(_ events: [CorrectionEvent],
                      recordTerm: (_ term: String, _ heard: String?) -> Bool,
                      learn: (CorrectionPair) -> Void,
                      veto: (CorrectionPair) -> Void) -> (learned: Int, vetoed: Int) {
        var learned = 0, vetoed = 0
        for event in events {
            switch event {
            case .learn(let p):
                if recordTerm(p.term, p.heard) {
                    learn(p)
                    learned += 1
                }
            case .hotword(let t):
                if recordTerm(t, nil) { learned += 1 }
            case .veto(let p):
                veto(p)
                vetoed += 1
            }
        }
        return (learned, vetoed)
    }

    /// A voice result about to be typed: learned rules, with AutoSpace
    /// before and after when it is on. Rules are learned from field text,
    /// which AutoSpace already spaced ("B 中"), so they must see spaced
    /// text; the second pass spaces the terms they put in.
    static func prepare(_ text: String, rules: [CorrectionPair], autoSpace: Bool) -> (text: String, applied: [CorrectionPair]) {
        let spaced = autoSpace ? AutoSpace.apply(text) : text
        let result = EditCorrection.apply(spaced, rules: rules)
        return (autoSpace ? AutoSpace.apply(result.text) : result.text, result.applied)
    }
}
