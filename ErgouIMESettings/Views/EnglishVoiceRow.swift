// ErgouIME Settings — 设置 › 语音 › 说中文出英文: its shortcut.
// SPDX-License-Identifier: GPL-3.0-only
//
// Not set by default, which means off ("清除" goes back to that). Usable
// only with 自动整理 = 云端 (Shared/EnglishVoice.swift); the row says so
// instead of hiding, so people can find the feature.

import SwiftUI

struct EnglishVoiceRow: View {
    /// Re-read after the voice key or the 中/英 key changed.
    let shortcuts: Shortcuts
    @State private var key = Shortcut(stored: Paths.sharedDefaults.string(forKey: SettingKey.englishVoiceShortcut))
    @AppStorage(SettingKey.voiceCorrection, store: Paths.sharedDefaults)
    private var correctionRaw = VoiceCorrection.apple.rawValue

    private var cloud: Bool { correctionRaw == VoiceCorrection.cloud.rawValue }

    /// Saved, but given way to the voice key or the 中/英 key since.
    private var clash: String? { key.flatMap { EnglishVoice.clash($0, with: shortcuts) } }

    var body: some View {
        LabeledContent {
            ShortcutRecorderRow(current: key, defaultTitle: "未设置",
                                reject: { new in new.flatMap { EnglishVoice.clash($0, with: Shortcuts.read()) } },   // nil: cleared, never a clash
                                save: save)
        } label: {
            Text("说中文出英文")
            Text(detail)
                .foregroundStyle(!cloud && key != nil || clash != nil ? Color.orange : Color.secondary)
        }
    }

    private var detail: String {
        if let clash { return "现在不能用：" + clash + "换一个键。" }
        if !cloud { return "要先把下面的“自动整理”设为云端。说的中文识别后发给你的云端模型写成英文，再打进去。" }
        guard let key else { return "录一个快捷键就能用：用它开始说话，说完打出来的是英文。也可以用开始 / 结束键说着说着改按这个键，这次就出英文。" }
        let verb = key.isTap ? "点" : "按"
        return "\(verb) \(key.title) 开始说中文，再\(verb)一下结束，打出来的是英文；用开始 / 结束键说着的时候\(verb)它，也出英文。整段话说完后发一次，翻译失败就输入中文。"
    }

    private func save(_ new: Shortcut?) {
        if let new {
            Paths.sharedDefaults.set(new.stored, forKey: SettingKey.englishVoiceShortcut)
        } else {
            Paths.sharedDefaults.removeObject(forKey: SettingKey.englishVoiceShortcut)
        }
        key = new
        // A modifier tap needs Input Monitoring like the voice key; a key
        // with ⌃ ⌥ ⌘ becomes a hot key. The input method re-reads both.
        SharedNotifications.post(SharedNotifications.globalVoiceChanged)
    }
}
