// ergou-ime — validation of values that cross from Settings to the input method.
// SPDX-License-Identifier: GPL-3.0-only
//
// The shared UserDefaults can be written by ErgouIME Settings, which has
// network access. The input method therefore treats everything read from it
// as untrusted: only whitelisted values survive, and nothing read from it is
// ever copied into a Rime file without passing these checks. Settings runs
// the same checks before saving, so the user sees errors early.

import Foundation

struct ManualPhrase: Hashable {
    /// 1–8 CJK characters.
    let text: String
    /// 1–4 keys a–y (wubi 86 does not use z).
    let code: String
}

enum SettingsValidation {
    static let maxManualPhrases = 2000
    static let maxPhraseLength = 8

    static func fuzzyPinyin(_ raw: Any?) -> [FuzzyPinyin] {
        guard let list = raw as? [String] else { return FuzzyPinyin.defaults }
        // Canonical order; unknown ids and duplicates disappear.
        let chosen = Set(list.compactMap(FuzzyPinyin.init(rawValue:)))
        return FuzzyPinyin.allCases.filter(chosen.contains)
    }

    static func manualPhrases(_ raw: Any?) -> [ManualPhrase] {
        guard let list = raw as? [String] else { return [] }
        var result: [ManualPhrase] = []
        var seen = Set<ManualPhrase>()
        for line in list.prefix(maxManualPhrases) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let phrase = manualPhrase(text: String(parts[0]), code: String(parts[1])),
                  seen.insert(phrase).inserted
            else { continue }
            result.append(phrase)
        }
        return result
    }

    /// nil unless text is 1–8 CJK ideographs and code is 1–4 letters a–y.
    /// This excludes tabs, newlines, YAML syntax and anything else that could
    /// change the meaning of the generated dict.yaml.
    static func manualPhrase(text: String, code: String) -> ManualPhrase? {
        guard (1...maxPhraseLength).contains(text.count),
              text.unicodeScalars.allSatisfy(isCJKIdeograph),
              (1...4).contains(code.count),
              code.unicodeScalars.allSatisfy({ ("a"..."y").contains($0) })
        else { return nil }
        return ManualPhrase(text: text, code: code)
    }

    private static func isCJKIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,   // Extension A
             0x4E00...0x9FFF,   // Unified Ideographs
             0xF900...0xFAFF,   // Compatibility Ideographs
             0x20000...0x3134F: // Extensions B–G
            return true
        default:
            return false
        }
    }
}

// MARK: - 常用语

/// A saved phrase (D, 2026-11-09): text, optionally reached by a short code.
struct QuickPhrase: Hashable, Identifiable {
    var id: String { code + "\u{1}" + text }
    /// 0–8 letters a–z; empty = only from the 常用语 window.
    let code: String
    /// 1–500 characters; may span lines; no tabs or control characters.
    let text: String

    /// Stored as "code<TAB>text" with newlines written as "\n".
    var stored: String {
        code + "\t" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
    }
}

extension SettingsValidation {
    static let maxQuickPhrases = 999
    static let maxQuickPhraseLength = 500

    static func quickPhrase(code: String, text: String) -> QuickPhrase? {
        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let code = code.lowercased()
        guard (1...maxQuickPhraseLength).contains(text.count),
              !text.unicodeScalars.contains(where: { $0 == "\t" || ($0.properties.generalCategory == .control && $0 != "\n") }),
              code.count <= 8,
              code.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) })
        else { return nil }
        return QuickPhrase(code: code, text: text)
    }

    /// Drops repeated entries (same code and text), keeping the first:
    /// QuickPhrase.id must be unique for SwiftUI lists.
    static func uniqued(_ phrases: [QuickPhrase]) -> [QuickPhrase] {
        var seen = Set<QuickPhrase>()
        return phrases.filter { seen.insert($0).inserted }
    }

    static func quickPhrases(_ raw: Any?) -> [QuickPhrase] {
        guard let list = raw as? [String] else { return [] }
        var out: [QuickPhrase] = []
        for line in list.prefix(maxQuickPhrases) {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let code = String(line[..<tab])
            var text = ""
            var escape = false
            for ch in line[line.index(after: tab)...] {
                if escape { text.append(ch == "n" ? "\n" : ch); escape = false }
                else if ch == "\\" { escape = true }
                else { text.append(ch) }
            }
            if let p = quickPhrase(code: code, text: text) { out.append(p) }
        }
        return uniqued(out)
    }
}

extension SettingKey {
    /// [String], QuickPhrase.stored lines.
    static let quickPhrases = "quickPhrases"
}

extension SharedNotifications {
    /// Settings saved 常用语: the input method rewrites ergou_phrases.txt
    /// only (no redeploy; lua/ergou/phrases.lua notices the change).
    static let regeneratePhrases = "com.codamon.ergou.regenerate-phrases"
}

extension SharedSettings {
    static var quickPhrases: [QuickPhrase] {
        SettingsValidation.quickPhrases(Paths.sharedDefaults.object(forKey: SettingKey.quickPhrases))
    }

    static func saveQuickPhrases(_ phrases: [QuickPhrase]) {
        Paths.sharedDefaults.set(phrases.prefix(SettingsValidation.maxQuickPhrases).map(\.stored),
                                 forKey: SettingKey.quickPhrases)
    }
}
