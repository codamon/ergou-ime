// ergou-ime — 说中文出英文: the answer checks, chunks and the shortcut clash rules.
// SPDX-License-Identifier: GPL-3.0-only

let englishVoiceTests: [Test] = [
    ("english: a normal answer is taken", {
        let input = "嗯，那个，明天下午三点我们在二楼会议室开个会，记得带电脑。"
        let raw = #"{"text": "Let's meet in the second-floor meeting room at 3 p.m. tomorrow. Remember to bring your laptop."}"#
        expect(CloudTidy.parseEnglish(raw, input: input),
               "Let's meet in the second-floor meeting room at 3 p.m. tomorrow. Remember to bring your laptop.", "parsed")
        expect(CloudTidy.parseEnglish("```json\n" + raw + "\n```", input: input) != nil, true, "code fence is fine")
    }),
    ("english: a Chinese answer is refused", {
        let input = "明天下午三点开会。"
        expect(CloudTidy.parseEnglish(#"{"text": "明天下午三点开会。"}"#, input: input), nil, "the Chinese back")
        expect(CloudTidy.parseEnglish(#"{"text": "好的，明天下午三点开会。"}"#, input: input), nil, "a Chinese reply")
        expect(CloudTidy.parseEnglish(#"{"text": "Meeting with 张伟 at 3 p.m. tomorrow."}"#, input: "明天下午三点和张伟开会。") != nil,
               true, "a name left in Chinese is fine")
    }),
    ("english: length guard", {
        let input = "我同意。"
        check(CloudTidy.looksTranslated("I agree.", for: input), "short is fine")
        check(!CloudTidy.looksTranslated("", for: input), "empty")
        let lecture = String(repeating: "Here is a detailed explanation of agreement. ", count: 10)
        check(!CloudTidy.looksTranslated(lecture, for: input), "an answer far longer than what was said")
        let long = String(repeating: "我们下周把这个功能做完。", count: 20)
        check(!CloudTidy.looksTranslated("OK.", for: long), "a long dictation does not become two letters")
        check(CloudTidy.looksTranslated("OK", for: "嗯嗯嗯好的"), "fillers make it short")
    }),
    ("english: our tags and the app name are refused", {
        expect(CloudTidy.parseEnglish(#"{"text": "<识别结果>Hello</识别结果>"}"#, input: "你好"), nil, "tag echo")
        expect(CloudTidy.parseEnglish(#"{"text": "Slack"}"#, input: "被网易八哥说。", app: "Slack"), nil, "app name")
        expect(CloudTidy.parseEnglish(#"{"text": "Send it on Slack."}"#, input: "在 Slack 上发。", app: "Slack") != nil,
               true, "app name that was said")
        expect(CloudTidy.parseEnglish("not json", input: "你好"), nil, "not JSON")
    }),
    ("english: chunks at sentence ends", {
        let s = String(repeating: "这是一句话。", count: 300)               // 1800 characters
        let chunks = CloudTidy.translateChunks(s)
        check(chunks.count > 1, "cut")
        check(chunks.allSatisfy { $0.count <= CloudTidy.translateChunk }, "each within the limit")
        check(chunks.allSatisfy { $0.hasSuffix("。") }, "at sentence ends")
        expect(chunks.joined(), s, "nothing lost")
        let run = String(repeating: "字", count: 4000)
        check(CloudTidy.translateChunks(run).allSatisfy { $0.count <= 1800 }, "no sentence end: still under the service limit")
        expect(CloudTidy.translateChunks("  \n"), [], "blank")
        expect(CloudTidy.joinEnglish(["Hello. ", "", " World."]), "Hello. World.", "joined with one space")
    }),
    ("english: request picks the prompt", {
        var r = CloudTidy.Request(text: "你好", context: nil, app: nil)
        check(CloudTidy.system(for: r) == CloudTidy.system, "tidy-up")
        r.english = true
        check(CloudTidy.system(for: r) == CloudTidy.systemEnglish, "english")
        r.whole = true
        check(CloudTidy.system(for: r) == CloudTidy.systemEnglish, "english wins over whole")
    }),
    ("english: shortcut clashes", {
        var s = Shortcuts()
        expect(EnglishVoice.clash(.tap(Shortcut.rightOption), with: s) != nil, true, "the voice key")
        expect(EnglishVoice.clash(.tap(Shortcut.rightShift), with: s) != nil, true, "Shift while Shift switches 中/英")
        expect(EnglishVoice.clash(.tap(54), with: s), nil, "Right Command is free")
        s.ascii = .tap(54)
        expect(EnglishVoice.clash(.tap(54), with: s) != nil, true, "the 中/英 key")
        expect(EnglishVoice.clash(.tap(Shortcut.rightShift), with: s), nil, "Shift is free once 中/英 moved")
    }),
]
