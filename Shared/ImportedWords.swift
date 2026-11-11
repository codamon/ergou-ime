// ergou-ime — 个人词库: words imported from another input method.
// SPDX-License-Identifier: GPL-3.0-only
//
// ErgouIME Settings parses the file the user picked (Sogou / QQ / Baidu /
// Rime exports, plain word lists; ErgouIMESettings/Model/PersonalDictionary
// Importer.swift) and writes the result to the App Group container as
//
//   Imported/pinyin-words.txt     one word per line: "词" or "词<TAB>ci"
//                                 (pinyin syllables separated by spaces)
//
// The input method reads it, checks every line again with the same rules
// (Settings has network access and is not trusted), and turns it into two
// Rime tables in its own user directory, imported by ergou_pinyin_dict
// after the main dictionary (ErgouIME/Engine/PinyinDictionary.swift):
//
//   ergou_imported.dict.yaml       words with pinyin
//   ergou_imported_auto.dict.yaml  words without; Rime spells them from
//                                  the character readings (polyphones get
//                                  every reading: 长乐 → chang le, zhang le)
//
// Because the main dictionary comes first, a word it already has keeps its
// own weight; imported words only add what was missing. They get a fixed
// weight around the 95th percentile of rime-ice's words, high enough to be
// offered, not enough to push aside the most common words.

import Foundation

struct ImportedWord: Hashable {
    let text: String
    /// "ni hao", or nil: Rime spells it.
    let pinyin: String?

    var stored: String { pinyin.map { "\(text)\t\($0)" } ?? text }
}

enum ImportedWords {
    static let maxWords = 100_000
    static let maxLength = 16
    static let weight = 50_000
    static let maxFileBytes = 8 << 20

    static var file: URL {
        Paths.root.appendingPathComponent("Imported", isDirectory: true)
            .appendingPathComponent("pinyin-words.txt")
    }

    /// 2…16 Han characters (single characters are already in every table).
    static func validText(_ text: String) -> Bool {
        (2...maxLength).contains(text.count)
            && text.unicodeScalars.allSatisfy { $0.properties.isIdeographic }
    }

    /// One a–z (v for ü) syllable of 1–6 letters per character.
    static func validPinyin(_ pinyin: String, for text: String) -> Bool {
        let syllables = pinyin.split(separator: " ", omittingEmptySubsequences: false)
        return syllables.count == text.count
            && syllables.allSatisfy { s in (1...6).contains(s.count) && s.unicodeScalars.allSatisfy { ("a"..."z").contains($0) } }
    }

    /// Parses one stored line; nil if it does not pass the rules above.
    static func word(fromStored line: Substring) -> ImportedWord? {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let text = String(parts[0])
        guard validText(text) else { return nil }
        if parts.count == 2 {
            let pinyin = String(parts[1])
            guard validPinyin(pinyin, for: text) else { return nil }
            return ImportedWord(text: text, pinyin: pinyin)
        }
        return ImportedWord(text: text, pinyin: nil)
    }

    /// The stored list, validated. Empty if missing or too big.
    static func load() -> [ImportedWord] {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attrs[.size] as? NSNumber, size.intValue <= maxFileBytes,
              let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var seen = Set<ImportedWord>()
        var out: [ImportedWord] = []
        for line in text.split(separator: "\n") {
            guard out.count < maxWords, let word = word(fromStored: line), seen.insert(word).inserted else { continue }
            out.append(word)
        }
        return out
    }

    /// Settings only.
    static func save(_ words: [ImportedWord]) throws {
        let dir = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = words.prefix(maxWords).map(\.stored).joined(separator: "\n")
        try (body.isEmpty ? "" : body + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: file)
    }
}
