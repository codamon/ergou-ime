// ergou-ime — the input method's side of 我的词 (Shared/VoiceTerms.swift).
// SPDX-License-Identifier: GPL-3.0-only
//
// Owns the learned-terms file (only this process writes it), applies the
// edits Settings asks for, and keeps the hotword string for the recogniser.
// The string is rebuilt only when something changed (dirty flag), never per
// segment; the recogniser takes it per stream, so the model is not reloaded.
// Main thread only.

import Foundation

final class TermStore {
    static let shared = TermStore(file: Paths.learnedTerms, defaults: Paths.sharedDefaults)

    private let file: URL
    private let defaults: UserDefaults
    private var learned = LearnedTermsFile()
    private var dirty = true
    private var cached = ""
    private var observers: [NSObjectProtocol] = []
    /// Replaceable for tests (an SSH session sees the locked screen's secure input).
    var isSecureInput: () -> Bool = { SecureInput.isActive }

    init(file: URL, defaults: UserDefaults) {
        self.file = file
        self.defaults = defaults
        load()
    }

    /// Listen for Settings' changes (call once, from the input method's start-up).
    func start() {
        observers.append(SharedNotifications.observe(SharedNotifications.voiceTermsChanged) { [weak self] in
            self?.settingsChanged()
        })
        applyPendingEdits()
    }

    /// Comma-separated terms for Qwen3-ASR; "" when there are none.
    var hotwords: String {
        if dirty {
            applyPendingEdits()
            let manual = VoiceTermRules.manual(defaults.object(forKey: SettingKey.voiceTermsManual))
            cached = VoiceTermRules.hotwordString(VoiceTermRules.effective(manual: manual, learned: learned.terms))
            dirty = false
        }
        return cached
    }

    /// The terms in `hotwords`, in priority order (sent to the cloud tidy-up).
    var activeTerms: [String] {
        hotwords.isEmpty ? [] : hotwords.split(separator: ",").map(String.init)
    }

    /// Number of terms in `hotwords`, for the diagnostics line.
    var activeCount: Int { hotwords.isEmpty ? 0 : hotwords.split(separator: ",").count }

    /// A term the user evidently meant (e.g. the tidy-up step replaced
    /// `heard` with `term`). Ignored while secure input is on (rule 6).
    func record(term: String, heard: String?, source: TermSource) {
        guard !isSecureInput(),
              VoiceTermRules.record(&learned, term: term, heard: heard, source: source) else { return }
        dirty = true
        save()
    }

    var learnedTerms: [LearnedTerm] { learned.terms }

    func settingsChanged() {
        dirty = true
        applyPendingEdits()
    }

    /// Settings' 删除 / 固定 requests: apply, save, then drop exactly the
    /// requests we applied (Settings may have appended more meanwhile).
    private func applyPendingEdits() {
        let raw = defaults.stringArray(forKey: SettingKey.voiceTermEdits) ?? []
        guard !raw.isEmpty else { return }
        let edits = VoiceTermRules.edits(raw)
        VoiceTermRules.apply(edits, to: &learned)
        save()
        let now = defaults.stringArray(forKey: SettingKey.voiceTermEdits) ?? []
        let rest = VoiceTermRules.editsLeft(now: now, applied: raw)
        if rest.isEmpty { defaults.removeObject(forKey: SettingKey.voiceTermEdits) }
        else if rest.count != now.count { defaults.set(rest, forKey: SettingKey.voiceTermEdits) }
        dirty = true
    }

    private func load() {
        // The App Group container is writable by Settings: re-validate.
        // …and never read a link, a FIFO or something huge (audit L11).
        guard let data = SafeFile.read(file, maxBytes: 1 << 20) else { return }
        learned = VoiceTermRules.decodeFile(data)
    }

    private func save() {
        guard let data = VoiceTermRules.encodeFile(learned) else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            Log.speech.error("Could not save learned terms")
        }
    }
}
