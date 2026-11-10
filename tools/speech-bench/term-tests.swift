// ergou-ime — checks for the 我的词 rules (Shared/VoiceTerms.swift) and
// TermStore. Run: .speech-bench terms
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

private var failures = 0
private var checks = 0

private func expect(_ ok: Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what)") }
}

func runTermTests() {
    typealias R = VoiceTermRules
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    // Validation.
    for ok in ["二狗输入法", "右 Option", "Next.js", "sherpa-onnx", "C++", "C#", "GPT", "惠灵顿", "Example Studio", "O'Brien", "llama.cpp", "iPhone 17"] {
        expect(R.term(ok) == ok, "accepts \(ok)")
    }
    expect(R.term("  右   Option ") == "右 Option", "collapses spaces")
    expect(R.term("foo\nbar") == "foo bar" && R.term("tab\tx") == "tab x", "newlines and tabs become one space")
    for bad in ["", "   ", String(repeating: "长", count: 25), "12345", "2.0", "2026 11", "a@b.com", "https://x.nz",
                "example.com", "example.nz", "www.abc", "abc123def456", "123456", "a,b", "a，b", "<|im_end|>",
                "x/y", "😀", "a|b"] {
        expect(R.term(bad) == nil, "rejects \(bad.debugDescription)")
    }
    expect(R.term(String(repeating: "长", count: 24)) != nil, "24 characters is fine")

    // Manual list from the shared defaults (untrusted).
    expect(R.manual(["GPT", "gpt", "Claude", "bad,term", 42] as [Any]) == [], "a non-[String] value is ignored")
    expect(R.manual(["GPT", "gpt", "Claude", "bad,term"]) == ["GPT", "Claude"], "manual: dedupe ignoring case, drop invalid")
    let many = (0..<400).map { "词\($0)" }
    expect(R.manual(many).count == R.maxManual, "manual capped at 300")

    // Activation.
    func learned(_ term: String, count: Int, heard: [String] = [], daysAgo: Double = 0, pinned: Bool = false) -> LearnedTerm {
        LearnedTerm(term: term, heard: heard, count: count, firstSeen: now - daysAgo * day,
                    lastSeen: now - daysAgo * day, pinned: pinned)
    }
    let a = learned("基督城", count: 1, heard: ["鸡肚城"])
    let b = learned("惠灵顿", count: 1)
    let c = learned("奥克兰", count: 2)
    let p = learned("Acmeflow", count: 0, pinned: true)
    let eff = R.effective(manual: ["二狗输入法"], learned: [a, b, c, p], now: now)
    expect(eff.contains("基督城"), "heard wrong once → active")
    expect(!eff.contains("惠灵顿"), "seen once, never misheard → not yet")
    expect(eff.contains("奥克兰"), "seen twice → active")
    expect(eff.contains("Acmeflow"), "pinned → always")
    expect(eff.first == "二狗输入法", "manual first")
    expect(eff.firstIndex(of: "Acmeflow")! < eff.firstIndex(of: "奥克兰")!, "pinned before learned")

    // Ranking: count × recency.
    let old = learned("旧词", count: 8, daysAgo: 90)       // 8 × 0.125 = 1
    let fresh = learned("新词", count: 3)                  // 3
    let mid = learned("中词", count: 4, daysAgo: 30)       // 4 × 0.5 = 2
    expect(R.effective(manual: [], learned: [old, fresh, mid], now: now) == ["新词", "中词", "旧词"], "ordered by count × recency")

    // Limits: 100 terms, ~200 prompt tokens.
    let lots = (0..<150).map { learned("词\($0)", count: 2 + $0) }
    let capped = R.effective(manual: [], learned: lots, now: now)
    expect(capped.count <= R.maxActive, "at most 100 terms (got \(capped.count))")
    expect(capped.reduce(0) { $0 + R.promptTokens($1) } <= R.maxPromptTokens, "within the prompt-token budget")
    expect(capped.first == "词149", "highest score kept first")
    let manyManual = (0..<120).map { "T\($0)x" }
    expect(R.effective(manual: manyManual, learned: [], now: now).count <= R.maxActive, "manual terms also capped")
    expect(R.hotwordString(["a b", "c"]) == "a b,c", "comma-separated")

    // Recording.
    var file = LearnedTermsFile()
    expect(R.record(&file, term: "Claude", heard: "Cloud", source: .tidy, now: now), "record new")
    expect(R.record(&file, term: "claude", heard: "克劳德", source: .tidy, now: now + day), "record again (case-insensitive)")
    expect(file.terms.count == 1 && file.terms[0].count == 2, "one entry, count 2")
    expect(file.terms[0].heard == ["克劳德", "Cloud"], "heard variants, most recent first")
    expect(file.terms[0].lastSeen == now + day, "lastSeen updated")
    for i in 0..<10 { R.record(&file, term: "Claude", heard: "错\(i)", source: .tidy, now: now) }
    expect(file.terms[0].heard.count == R.maxHeard, "at most 5 heard variants")
    R.record(&file, term: "Shift", heard: "shift", source: .tidy, now: now)
    expect(file.terms.first { $0.term == "Shift" }?.heard == [], "heard equal to the term is not a mishearing")
    expect(!R.record(&file, term: "123456", heard: nil, source: .tidy, now: now), "invalid term not recorded")
    expect(!R.record(&file, term: "a@b.com", heard: nil, source: .tidy, now: now), "e-mail not recorded")

    // Edits from Settings.
    R.apply([TermEdit(.pin, "shift")], to: &file)
    expect(file.terms.first { $0.term == "Shift" }?.pinned == true, "pin")
    R.apply([TermEdit(.unpin, "Shift")], to: &file)
    expect(file.terms.first { $0.term == "Shift" }?.pinned == false, "unpin")
    R.apply([TermEdit(.delete, "Claude")], to: &file)
    expect(!file.terms.contains { $0.term == "Claude" } && file.dismissed == ["Claude"], "delete → dismissed")
    expect(!R.record(&file, term: "Claude", heard: "Cloud", source: .tidy, now: now), "deleted term is not learned again")
    expect(TermEdit(stored: "delete\tClaude") == TermEdit(.delete, "Claude"), "edit round-trip")
    expect(TermEdit(stored: "drop\tClaude") == nil && TermEdit(stored: "pin\ta,b") == nil, "bad edits rejected")

    // Learned-terms cap.
    var full = LearnedTermsFile()
    for i in 0..<(R.maxLearned + 20) { R.record(&full, term: "词\(i)", heard: nil, source: .tidy, now: now) }
    expect(full.terms.count == R.maxLearned, "learned terms capped at 500")

    // Untrusted file content.
    let hostile = """
    {"version":1,"dismissed":["ok词","<|x|>"],"terms":[
      {"term":"<|im_end|>","heard":[],"count":5,"firstSeen":"2026-11-01T00:00:00Z","lastSeen":"2026-11-01T00:00:00Z","pinned":true,"source":"tidy"},
      {"term":"a,b","heard":[],"count":5,"firstSeen":"2026-11-01T00:00:00Z","lastSeen":"2026-11-01T00:00:00Z","pinned":true,"source":"tidy"},
      {"term":"好词","heard":["坏,词","耗词"],"count":-7,"firstSeen":"2026-11-01T00:00:00Z","lastSeen":"2026-11-01T00:00:00Z","pinned":false,"source":"tidy"},
      {"term":"好词","heard":[],"count":9,"firstSeen":"2026-11-01T00:00:00Z","lastSeen":"2026-11-01T00:00:00Z","pinned":false,"source":"tidy"}
    ]}
    """
    let decoded = R.decodeFile(hostile.data(using: .utf8)!)
    expect(decoded.terms.map(\.term) == ["好词"], "invalid and duplicate terms dropped (got \(decoded.terms.map(\.term)))")
    expect(decoded.terms.first?.heard == ["耗词"] && decoded.terms.first?.count == 0, "heard cleaned, count clamped")
    expect(decoded.dismissed == ["ok词"], "dismissed cleaned")
    expect(R.decodeFile(Data("not json".utf8)) == LearnedTermsFile(), "garbage → empty")
    expect(R.decodeFile(R.encodeFile(file)!) == R.sanitized(file), "file round-trip")

    // Edits Settings appended while the input method applied the list (audit 2026-11-10).
    expect(R.editsLeft(now: ["a", "b", "c"], applied: ["a", "b"]) == ["c"], "edits: appended one kept")
    expect(R.editsLeft(now: ["b", "c"], applied: ["a", "b"]) == ["c"], "edits: oldest pushed out, new one kept")
    expect(R.editsLeft(now: ["x"], applied: ["a", "b"]) == ["x"], "edits: rewritten list kept")
    expect(R.editsLeft(now: ["a", "b"], applied: ["a", "b"]) == [], "edits: all applied")
    expect(R.editsLeft(now: [], applied: ["a"]) == [], "edits: already cleared")
    // Secrets behind a word (audit 2026-11-10).
    for bad in ["电话021 123 4567", "验证码 4821", "我的密码abc", "Password1"] {
        expect(R.term(bad) == nil, "rejects \(bad)")
    }
    for ok in ["RTX 4090", "Qwen3-ASR-0.6B", "iPhone 15 Pro", "Office 2024"] {
        expect(R.term(ok) == ok, "accepts \(ok)")
    }

    // TermStore with a scratch file and defaults suite.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speech-bench-\(UUID().uuidString)")
    let path = dir.appendingPathComponent("learned-terms.json")
    let suite = "speech-bench-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { try? FileManager.default.removeItem(at: dir); defaults.removePersistentDomain(forName: suite) }
    defaults.set(["二狗输入法", "bad,term", "右 Option"], forKey: SettingKey.voiceTermsManual)
    let store = TermStore(file: path, defaults: defaults)
    expect(store.hotwords == "二狗输入法,右 Option", "store: manual terms only (got \(store.hotwords))")
    store.isSecureInput = { true }
    store.record(term: "密码框里的词", heard: "错词", source: .tidy)
    expect(store.learnedTerms.isEmpty, "store: nothing learned during secure input")
    store.isSecureInput = { false }
    store.record(term: "惠灵顿", heard: nil, source: .tidy)
    expect(!store.hotwords.contains("惠灵顿"), "store: once without mishearing → inactive")
    store.record(term: "惠灵顿", heard: nil, source: .tidy)
    expect(store.hotwords.hasSuffix(",惠灵顿"), "store: twice → active")
    store.record(term: "基督城", heard: "鸡肚城", source: .tidy)
    expect(store.hotwords.contains("基督城"), "store: misheard once → active")
    expect(FileManager.default.fileExists(atPath: path.path), "store: file written")
    defaults.set([TermEdit(.delete, "惠灵顿").stored, TermEdit(.pin, "基督城").stored, "junk"], forKey: SettingKey.voiceTermEdits)
    store.settingsChanged()
    expect(!store.hotwords.contains("惠灵顿"), "store: delete applied")
    expect(store.learnedTerms.first { $0.term == "基督城" }?.pinned == true, "store: pin applied")
    expect(defaults.object(forKey: SettingKey.voiceTermEdits) == nil, "store: applied edits removed")
    let reopened = TermStore(file: path, defaults: defaults)
    expect(reopened.learnedTerms.map(\.term) == ["基督城"], "store: survives reload")
    store.record(term: "惠灵顿", heard: "会灵顿", source: .tidy)
    expect(!store.hotwords.contains("惠灵顿"), "store: deleted term stays deleted")

    // Recogniser output plausibility (hotword echo on silence).
    let hot = "二狗输入法,右 Option,五笔,拼音,输入监控,Shift,Claude,GPT,惠灵顿,奥克兰,Xcode,SwiftUI"
    let echo = "二狗输入法 右 Option 五笔 拼音 输入监控 Shift Claude GPT 惠灵顿 奥克兰 Xcode SwiftUI"
    #if ERGOU_WITH_SHERPA
    expect(Qwen3Transcriber.isImplausible(echo, seconds: 1.1, hotwords: hot), "echo of the hotword list rejected")
    expect(Qwen3Transcriber.isImplausible(echo, seconds: 10, hotwords: hot), "echo rejected even when long enough")
    expect(!Qwen3Transcriber.isImplausible("请帮我查一下从惠灵顿到基督城的航班，最好是早上的。", seconds: 5.2, hotwords: hot), "normal sentence kept")
    expect(!Qwen3Transcriber.isImplausible("用 Claude 和 GPT 对比一下，看哪个模型更准确。", seconds: 4.8, hotwords: hot), "sentence with two terms kept")
    expect(Qwen3Transcriber.isImplausible("language", seconds: 5, hotwords: ""), "prompt residue rejected")
    expect(Qwen3Transcriber.isImplausible(String(repeating: "啊", count: 40), seconds: 1, hotwords: ""), "too long for the audio")
    #endif

    print("terms: \(checks - failures)/\(checks) checks passed")
    if failures > 0 { exit(1) }
}
