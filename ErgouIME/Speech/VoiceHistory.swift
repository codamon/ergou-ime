// ergou-ime — local history of voice results (D, 2026-11-09).
// SPDX-License-Identifier: GPL-3.0-only
//
// Clipboard history is deliberately not kept; voice history is, because a
// long dictation is costly to lose. Rules:
//   - stored only in the input method's own sandbox container
//     (Paths.privateRoot); ErgouIME Settings (which has network access)
//     cannot read it, it can only ask us to clear it;
//   - nothing is recorded in password fields (Privacy rule 6), and text that
//     looks like a secret is never stored (passwords, codes, keys);
//   - last 200 entries, 30 days; off switch and "clear" in Settings.

import Foundation

final class VoiceHistory {
    static let shared = VoiceHistory()

    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var text: String
        var date: Date
    }

    private(set) var entries: [Entry] = []
    private let file = Paths.privateRoot.appendingPathComponent("voice-history.json")
    private static let maxEntries = 200
    private static let maxAge: TimeInterval = 30 * 24 * 3600

    private init() { load() }

    func add(_ text: String) {
        guard SharedSettings.voiceHistoryEnabled, !Self.isSensitive(text) else { return }
        prune()
        entries.insert(Entry(text: text, date: Date()), at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        save()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: file)
    }

    var recent: [Entry] { prune(); return entries }

    /// Looks like a password, one-time code or key: never stored.
    static func isSensitive(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = ["密码", "口令", "验证码", "校验码", "动态码", "pin码", "password", "passcode", "passwd", "otp", "secret", "token", "api key", "apikey", "私钥", "助记词"]
        if words.contains(where: { lower.contains($0) }) { return true }
        // A run of 6+ digits (codes, card numbers) or an 8+ character run
        // mixing letters and digits (keys, generated passwords).
        let runs = text.split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) })
        for run in runs {
            let digits = run.filter(\.isNumber).count
            let letters = run.filter(\.isLetter).count
            if digits >= 6 && letters == 0 { return true }
            if run.count >= 8 && digits >= 2 && letters >= 2 { return true }
        }
        return false
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        let before = entries.count
        entries.removeAll { $0.date < cutoff }
        if entries.count != before { save() }
    }

    private func load() {
        // Turned off while we were not running (the clear request had no
        // one to receive it): delete what is left.
        guard SharedSettings.voiceHistoryEnabled else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        guard let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = saved
        prune()                                       // also drops expired entries from the file
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        do {
            try data.write(to: file, options: [.atomic, .completeFileProtection])
        } catch {
            // Data protection classes may not be available for this file on
            // macOS; the container is still private to us. Never lose the
            // history silently because of it.
            do {
                try data.write(to: file, options: .atomic)
            } catch {
                Log.speech.error("Could not save voice history")
            }
        }
    }
}
