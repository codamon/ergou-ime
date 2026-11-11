// ergou-ime — tests for the tidy-up answer guards (Shared/CorrectionPrompt.swift,
// Shared/CloudTidy.swift): braces the model added, and answers that are the
// app's name.
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

let tidyGuardTests: [Test] = [
    ("addedBracesRemovedLocal", {
        expect(CorrectionPrompt.accept("被网易{Bugo}说。", for: "被网易bugo说。"), "被网易Bugo说。", "local tidy-up")
    }),
    ("addedBracesRemovedCloud", {
        let p = CloudTidy.parse("{\"text\": \"被网易{Bugo}说。\", \"terms\": [{\"term\": \"Bugo\", \"heard\": \"八哥\"}]}",
                                input: "被网易八哥说。")
        expect(p?.text, "被网易Bugo说。", "braces stripped")
        expect(p?.terms.map(\.term), ["Bugo"], "term kept")
    }),
    ("fullWidthBracesRemoved", {
        expect(CorrectionPrompt.withoutAddedBraces("用｛Swift｝写", input: "用 swift 写"), "用Swift写", "full-width")
    }),
    ("bracesKeptWhenSaid", {
        expect(CorrectionPrompt.withoutAddedBraces("写成 {name}", input: "写成 {name}"), "写成 {name}", "input had braces")
    }),
    ("appNameEchoRefused", {
        let raw = "{\"text\": \"备忘录\", \"terms\": []}"
        check(CloudTidy.parse(raw, input: "被网易八哥说。", app: "备忘录") == nil, "answer is the app name")
        check(CloudTidy.parse("{\"text\": \"备忘录，不够说。\"}", input: "被网易不够说。", app: "备忘录") == nil,
              "answer starts with the app name")
    }),
    ("appNameAllowedWhenSaid", {
        let p = CloudTidy.parse("{\"text\": \"发到 Slack 上。\"}", input: "发到 slack 上。", app: "Slack")
        expect(p?.text, "发到 Slack 上。", "user said the app's name")
    }),
    ("noAppNoCheck", {
        check(CloudTidy.parse("{\"text\": \"备忘录\"}", input: "被网易八哥说。") != nil, "without app the old rules apply")
    }),
]
