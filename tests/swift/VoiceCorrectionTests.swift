// ergou-ime — tests for VoiceCorrection.outcome (Shared/VoiceCorrection.swift).
// SPDX-License-Identifier: GPL-3.0-only
//
// Some strings differ from the plan's first draft so that each test stays
// within the learn-diff limits (at most 2 spans, changed ≤ half of the
// original) and tests the rule it is named after.

private func pair(_ heard: String, _ term: String) -> CorrectionPair { CorrectionPair(heard: heard, term: term) }

private func outcome(_ original: String, _ current: String, _ applied: [CorrectionPair] = []) -> [CorrectionEvent] {
    VoiceCorrection.outcome(original: original, current: current, applied: applied)
}

let voiceCorrectionTests: [Test] = [
    ("latinWordLearned", {
        expect(outcome("用 Orca 看一下", "用 rea 看一下"), [.learn(pair("Orca", "rea"))], "Orca → rea")
    }),
    ("latinWordExpandsToWholeWord", {
        expect(outcome("这个 SBP API 怎么计费的呢", "这个 sub2api 怎么计费的呢"),
               [.learn(pair("SBP API", "sub2api"))], "space-separated tokens merge")
    }),
    ("latinWordInnerDotKeptOuterDotDropped", {
        expect(outcome("我们用 Orca. 然后看一下这个程序", "我们用 rea. 然后看一下这个程序"),
               [.learn(pair("Orca", "rea"))], "sentence dot is not part of the word")
        expect(outcome("我们写一个 Nodes.js 的服务程序", "我们写一个 Node.js 的服务程序"),
               [.learn(pair("Nodes.js", "Node.js"))], "inner dot is part of the word")
    }),
    ("hanSingleCharPadsToThree", {
        expect(outcome("生肖日按审批", "生效日按审批"), [.learn(pair("生肖日", "生效日"))], "pad 1 left, 1 right")
    }),
    ("hanAtRunEdgePadsOtherSide", {
        expect(outcome("肖日审批", "效日审批"), [.learn(pair("肖日审", "效日审"))], "pad 2 right")
    }),
    ("hanShortRunOnlyHotword", {
        // The Han run 肖日 has only 2 characters: no rule, B is recorded.
        expect(outcome("Orca 肖日 Orca 和 Rhea", "Orca 效日 Orca 和 Rhea"), [.hotword("效日")], "run too short")
    }),
    ("hanMultiCharUsesSpan", {
        expect(outcome("B 中也是 USD", "币种也是 USD"), [.learn(pair("B 中", "币种"))], "mixed span as-is")
    }),
    ("hanSpanTooLongOnlyHotword", {
        expect(outcome("今天我们讨论一下甲乙丙丁戊己庚的事情吧好不好呀朋友们", "今天我们讨论一下天地玄黄宇宙洪的事情吧好不好呀朋友们"),
               [.hotword("天地玄黄宇宙洪")], "7 Han characters is more than 6")
    }),
    ("commonWordsLearnNothing", {
        expect(outcome("this is a test", "this is the test"), [], "a → the")
    }),
    ("commonHanWordLearnsNothing", {
        expect(outcome("我们今天但是要开会讨论", "我们今天所以要开会讨论"), [], "但是 → 所以")
    }),
    ("shortLatinOnlyHotword", {
        expect(outcome("用 RA 看", "用 REA 看"), [.hotword("REA")], "A has 2 characters")
    }),
    ("caseOnlyIgnored", {
        expect(outcome("用 orca", "用 Orca"), [], "short text")
        expect(outcome("我们用 orca 看一下这个程序", "我们用 Orca 看一下这个程序"), [], "within the limits")
    }),
    ("punctuationOnlyIgnored", {
        expect(outcome("要重新给。麦克风", "要重新给麦克风"), [], "deleted 。")
        expect(outcome("我们用 Orca 看一下这个程序", "我们用 Orca. 看一下这个程序"), [], "added .")
        expect(outcome("我们用 Orca，看一下这个程序", "我们用 Orca。看一下这个程序"), [], "，→ 。")
    }),
    ("pureDeletionIgnored", {
        expect(outcome("快速的狐狸", "狐狸"), [], "")
    }),
    ("pureInsertionInsideIgnored", {
        expect(outcome("我们用 Orca 看一下这个程序", "我们用 Orca 好好看一下这个程序"), [], "")
    }),
    ("wholeRewriteLearnsNothing", {
        expect(outcome("今天天气不错", "明天开会"), [], "")
    }),
    ("threeSpansLearnsNothing", {
        expect(outcome("我们用 Orca 写代码，用 Rust 做后端，用 Swift 做界面",
                       "我们用 rea 写代码，用 Rost 做后端，用 Swoft 做界面"), [], "")
    }),
    ("moreThanHalfLearnsNothing", {
        expect(outcome("Orca 看", "Rhea 看"), [], "4 of 6 characters changed")
        expect(outcome("用 Orca 看", "用 Rhea 看"), [.learn(pair("Orca", "Rhea"))], "4 of 8 is exactly half")
    }),
    ("trailingTypingIgnored", {
        expect(outcome("用 Orca 看一下", "用 rea 看一下吧好的"), [.learn(pair("Orca", "rea"))], "")
    }),
    ("trailingTypingAloneLearnsNothing", {
        expect(outcome("用 Orca 看一下", "用 Orca 看一下吧好的"), [], "")
    }),
    ("unchangedLearnsNothing", {
        expect(outcome("用 Orca 看一下", "用 Orca 看一下"), [], "")
        expect(outcome("", ""), [], "empty")
    }),
    ("twoSpansEachJudged", {
        expect(outcome("我用 Orca 测了 SBP API 的计费方式和请求次数", "我用 rea 测了 sub2api 的计费方式和请求次数"),
               [.learn(pair("Orca", "rea")), .learn(pair("SBP API", "sub2api"))], "in text order")
        expect(outcome("我用 Orca 测了 RA 的计费方式和请求次数", "我用 rea 测了 REA 的计费方式和请求次数"),
               [.learn(pair("Orca", "rea")), .hotword("REA")], "second span fails the guard")
    }),
    ("revertVetoes", {
        expect(outcome("我们用 rea 看一下这个程序", "我们用 Orca 看一下这个程序", [pair("Orca", "rea")]),
               [.veto(pair("Orca", "rea"))], "")
    }),
    ("revertIgnoresCase", {
        expect(outcome("我们用 rea 看一下这个程序", "我们用 orca 看一下这个程序", [pair("Orca", "rea")]),
               [.veto(pair("Orca", "rea"))], "")
    }),
    ("hanRevertVetoes", {
        expect(outcome("生效日按审批", "生肖日按审批", [pair("生肖日", "生效日")]),
               [.veto(pair("生肖日", "生效日"))], "")
    }),
    ("changeToThirdWord", {
        expect(outcome("我们用 rea 看一下这个程序", "我们用 Rhea 看一下这个程序", [pair("Orca", "rea")]),
               [.veto(pair("Orca", "rea")), .learn(pair("Orca", "Rhea"))], "")
    }),
    ("invalidTermDropped", {
        expect(outcome("发邮件给 Orca 吧", "发邮件给 rea@x 吧"), [], "@ is not allowed")
    }),
    ("commonWordsIgnoreCase", {
        check(CommonWords.contains("The"), "The")
        check(CommonWords.contains("this"), "this")
        check(CommonWords.contains("这个"), "这个")
        check(!CommonWords.contains("Orca"), "Orca")
        check(!CommonWords.contains("生肖日"), "生肖日")
    }),
]
