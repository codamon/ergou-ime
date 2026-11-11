// ErgouIME Settings — 导入个人词库 from another input method.
// SPDX-License-Identifier: GPL-3.0-only
//
// Reads a file the user picked (NSOpenPanel; files.user-selected.read-only)
// and never sends it anywhere. Understood:
//
//   text word lists, one entry per line, in UTF-8, UTF-16 (BOM) or GB18030:
//     'ni'hao 你好          Sogou .txt export
//     你好 ni hao 123       QQ / Baidu / Rime dict lines (any order, any
//     ni hao<TAB>你好        separator; a number is taken as a frequency
//     你好                  and ignored)
//   macOS 文本替换 (drag the list out of System Settings › Keyboard › Text
//   Replacements: "Text Substitutions.plist") → 常用语, the shortcut as code
//
// Words: 2–16 Han characters; anything with other characters is skipped.
// Pinyin is kept only when it has one syllable per character; otherwise
// Rime spells the word itself (Shared/ImportedWords.swift).
// Sogou .scel / .bin are binary formats and are not read.

import Foundation

struct PersonalDictionaryImport {
    var words: [ImportedWord] = []
    var phrases: [QuickPhrase] = []
    var skipped = 0

    enum Failure: Error {
        case unreadable, binary, tooBig, empty
        var message: String {
            switch self {
            case .unreadable: return "读不出这个文件的文字（不是 UTF-8、UTF-16 或 GBK 编码的文本）。"
            case .binary: return "这是二进制词库（如搜狗的 .scel / .bin），读不了。请在原输入法里“导出”为 .txt 文本再导入。"
            case .tooBig: return "文件太大（超过 \(ImportedWords.maxFileBytes >> 20) MB）。"
            case .empty: return "文件里没有找到可以导入的词。"
            }
        }
    }

    static func read(_ url: URL) -> Result<PersonalDictionaryImport, Failure> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Size first, then at most that much through one descriptor (not the
        // whole of a file that turns out to be gigabytes).
        let real = url.resolvingSymlinksInPath()
        if let size = (try? real.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > ImportedWords.maxFileBytes {
            return .failure(.tooBig)
        }
        guard let data = SafeFile.read(real, maxBytes: ImportedWords.maxFileBytes) else { return .failure(.unreadable) }
        if url.pathExtension.lowercased() == "plist" || data.starts(with: Array("bplist".utf8)) || data.starts(with: Array("<?xml".utf8)) {
            if let result = textReplacements(data) { return result.isEmpty ? .failure(.empty) : .success(result) }
        }
        let ext = url.pathExtension.lowercased()
        if ["scel", "bin", "dat"].contains(ext) { return .failure(.binary) }
        guard let text = decode(data) else { return .failure(.unreadable) }
        let result = words(text)
        return result.isEmpty ? .failure(.empty) : .success(result)
    }

    var isEmpty: Bool { words.isEmpty && phrases.isEmpty }

    // MARK: - Text

    private static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if let s = String(data: data, encoding: .utf8) { return s }
        // UTF-16 without BOM: many zero bytes.
        let zeros = data.prefix(4096).filter { $0 == 0 }.count
        if zeros > 64 { return String(data: data, encoding: .utf16LittleEndian) }
        if data.contains(0) { return nil }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: data, encoding: gb18030)
    }

    private static func words(_ text: String) -> PersonalDictionaryImport {
        var out = PersonalDictionaryImport()
        var seen = Set<String>()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") || line == "---" || line == "..." { continue }
            if line.hasSuffix(":") || line.contains(": ") { continue }   // YAML header of a Rime .dict.yaml
            guard let word = parse(line) else { out.skipped += 1; continue }
            guard seen.insert(word.text).inserted else { continue }
            out.words.append(word)
            if out.words.count >= ImportedWords.maxWords { break }
        }
        return out
    }

    /// One line → word (+ pinyin if it fits). nil: no usable word.
    private static func parse(_ line: String) -> ImportedWord? {
        // Sogou: 'ni'hao 你好 → tokens "'ni'hao", "你好"
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," || $0 == "，" || $0 == "=" })
            .map(String.init)
        let han = tokens.filter { ImportedWords.validText($0) }
        guard han.count == 1, let text = han.first else { return nil }
        // Everything made of letters/apostrophes is pinyin; numbers are frequencies.
        let letters = tokens.filter { $0 != text && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0 == "'") } }
        let syllables = letters.flatMap { $0.lowercased().replacingOccurrences(of: "ü", with: "v").split(separator: "'") }
            .map(String.init).filter { !$0.isEmpty }
        let pinyin = syllables.joined(separator: " ")
        return ImportedWord(text: text, pinyin: ImportedWords.validPinyin(pinyin, for: text) ? pinyin : nil)
    }

    // MARK: - macOS Text Replacements

    private static func textReplacements(_ data: Data) -> PersonalDictionaryImport? {
        guard let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { return nil }
        var out = PersonalDictionaryImport()
        for item in list {
            guard let phrase = item["phrase"] as? String else { out.skipped += 1; continue }
            let shortcut = (item["shortcut"] as? String ?? "").lowercased()
            // Codes are a–z only (常用语 rules); other shortcuts keep the phrase without a code.
            let code = shortcut.unicodeScalars.allSatisfy { ("a"..."z").contains($0) } && shortcut.count <= 8 ? shortcut : ""
            if let p = SettingsValidation.quickPhrase(code: code, text: phrase) { out.phrases.append(p) } else { out.skipped += 1 }
        }
        return out
    }
}

extension PersonalDictionaryImport {
    struct Summary {
        var wordsAdded = 0
        var wordsTotal = 0
        var phrasesAdded = 0
        var skipped = 0

        var message: String {
            var parts: [String] = []
            if wordsAdded > 0 || phrasesAdded == 0 { parts.append("新加了 \(wordsAdded) 个词（个人词库共 \(wordsTotal) 个）") }
            if phrasesAdded > 0 { parts.append("\(phrasesAdded) 条文本替换加进了常用语") }
            if skipped > 0 { parts.append("跳过 \(skipped) 行（不是纯汉字词或格式不对）") }
            return parts.joined(separator: "；") + "。"
        }
    }

    /// Merges into what was imported before and tells the input method.
    func apply() throws -> Summary {
        var summary = Summary(skipped: skipped)
        if !words.isEmpty {
            var merged = ImportedWords.load()
            // load() keeps one entry per word; uniquingKeysWith in case it ever does not.
            var index = Dictionary(merged.enumerated().map { ($1.text, $0) }, uniquingKeysWith: { first, _ in first })
            for word in words {
                if let i = index[word.text] {
                    if merged[i].pinyin == nil, word.pinyin != nil { merged[i] = word }   // keep the spelled one
                } else if merged.count < ImportedWords.maxWords {
                    index[word.text] = merged.count
                    merged.append(word)
                    summary.wordsAdded += 1
                }
            }
            try ImportedWords.save(merged)
            summary.wordsTotal = merged.count
            SharedNotifications.post(SharedNotifications.redeployRime)
        } else {
            summary.wordsTotal = ImportedWords.load().count
        }
        if !phrases.isEmpty {
            var current = SharedSettings.quickPhrases
            let known = Set(current.map(\.id))
            let fresh = phrases.filter { !known.contains($0.id) }
            current += fresh
            SharedSettings.saveQuickPhrases(current)
            summary.phrasesAdded = min(fresh.count, max(0, SettingsValidation.maxQuickPhrases - (current.count - fresh.count)))
            SharedNotifications.post(SharedNotifications.regeneratePhrases)
        }
        return summary
    }
}
