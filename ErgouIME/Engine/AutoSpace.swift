// ergou-ime — a space between Chinese and Latin letters/digits (盘古之白).
// SPDX-License-Identifier: GPL-3.0-only
//
// "用 macOS 开发" instead of "用macOS开发", like WeChat IME's
// 已自动帮你在中文和英文间添加空格. On by default; Settings → 输入.

import Foundation

enum AutoSpace {
    static func isHan(_ c: Character) -> Bool {
        c.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0x20000...0x3134F).contains($0.value) }
    }

    static func isLatin(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber)
    }

    static func needsSpace(_ a: Character, _ b: Character) -> Bool {
        (isHan(a) && isLatin(b)) || (isLatin(a) && isHan(b))
    }

    /// Insert spaces inside a piece of text (voice results).
    static func apply(_ text: String) -> String {
        var out = ""
        var previous: Character?
        for c in text {
            if let p = previous, needsSpace(p, c) { out.append(" ") }
            out.append(c)
            previous = c
        }
        return out
    }

    /// Text to insert after `before` (the character left of the caret).
    static func join(before: Character?, _ text: String) -> String {
        guard let before, let first = text.first, needsSpace(before, first) else { return text }
        return " " + text
    }
}
