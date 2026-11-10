// ergou-ime — 整句模型: the librime-octagram grammar used for whole sentences.
// SPDX-License-Identifier: GPL-3.0-only
//
// Optional, downloaded in Settings (one of two; only one grammar can be
// active in a schema). Measured 2026-11-11 on D's Mac with 拼音大词库, 121
// everyday clauses typed as full pinyin, first candidate = whole clause:
//
//   no model                  65 %   37 MB peak
//   轻量 bgw-compact (41 MB)   81 %   76 MB
//   万象 LMDG (418 MB)         83 %   391 MB
//
// Each with its publisher's recommended settings (lotem/rime-octagram-data
// grammar.yaml; amzxyz/rime_wanxiang wanxiang.schema.yaml): with the other
// one's settings wanxiang dropped to 78 %.
//
// Trust: Settings (network access) downloads the .gram into the App Group
// container. librime-octagram memory-maps and parses it in this process, so
// the input method copies it into its own Rime user directory, checks the
// COPY against the SHA-256 fixed in the code, and only then names it in the
// schema. It then deletes the downloaded original (the big one is 418 MB;
// keeping both would double the disk use). The folder's VERSION file stays
// as the "installed" marker; Settings deleting the folder means "remove".

import Foundation

enum GrammarModel: CaseIterable {
    case wanxiang
    case compact

    var files: SpeechModelFiles {
        switch self {
        case .wanxiang: return .grammarWanxiang
        case .compact: return .grammarCompact
        }
    }

    /// File name without .gram = grammar/language.
    var language: String {
        switch self {
        case .wanxiang: return "wanxiang-lts-zh-hans"
        case .compact: return "zh-hans-t-essay-bgw-compact"
        }
    }

    private var fileName: String { language + ".gram" }
    private var sha256: String { files.files[fileName]! }

    /// Patch lines for one schema: the `grammar` section plus the
    /// translator settings each publisher recommends, for every pinyin
    /// translator namespace in that schema ("translator", "pinyin", …).
    func patch(namespaces: [String]) -> String {
        var lines = ["  grammar:", "    language: \(language)"]
        var translator: [String]
        switch self {
        case .compact:
            translator = ["contextual_suggestions: true", "max_homophones: 7", "max_homographs: 7"]
        case .wanxiang:
            lines += ["    collocation_max_length: 6", "    collocation_min_length: 2",
                      "    collocation_penalty: -14", "    non_collocation_penalty: -6",
                      "    weak_collocation_penalty: -100", "    rear_penalty: -18"]
            translator = ["contextual_suggestions: false", "max_homophones: 8"]
        }
        for ns in namespaces { lines += translator.map { "  \(ns)/\($0)" } }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Brings the private copies in line with what Settings installed and
    /// returns the model to use (nil: none). Runs before every deployment.
    static func sync(_ user: URL) -> GrammarModel? {
        var active: GrammarModel?
        for model in allCases {
            if model.prepare(user), active == nil { active = model }
        }
        return active
    }

    /// True when `user/<language>.gram` is a checked copy and the model is
    /// still installed in Settings.
    private func prepare(_ user: URL) -> Bool {
        let fm = FileManager.default
        let local = user.appendingPathComponent(fileName)
        let marker = files.directory.appendingPathComponent("VERSION")
        guard fm.fileExists(atPath: marker.path) else {
            // Not installed (or deleted in Settings): drop our copy.
            if fm.fileExists(atPath: local.path) { try? fm.removeItem(at: local) }
            return false
        }
        let original = files.url(fileName)
        if fm.fileExists(atPath: original.path) {
            // A new download: copy, check the copy, then free the original.
            if !VerifiedFiles.shared.matches(local, sha256: sha256) {
                guard FileHash.sha256(of: original) == sha256 else {
                    Log.engine.error("Downloaded grammar model failed its check; not using it")
                    return false
                }
                let temp = user.appendingPathComponent(".\(UUID().uuidString).tmp")
                defer { try? fm.removeItem(at: temp) }
                do {
                    try fm.copyItem(at: original, to: temp)
                    guard FileHash.sha256(of: temp) == sha256 else {
                        Log.engine.error("Grammar model copy failed its check; not using it")
                        return false
                    }
                    if fm.fileExists(atPath: local.path) { try fm.removeItem(at: local) }
                    try fm.moveItem(at: temp, to: local)
                } catch {
                    Log.engine.error("Could not copy the grammar model; not using it")
                    return false
                }
            }
            try? fm.removeItem(at: original)
        }
        return VerifiedFiles.shared.matches(local, sha256: sha256)
    }
}
