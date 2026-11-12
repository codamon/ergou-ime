// ergou-ime — the 说中文出英文 shortcut as a system-wide hot key.
// SPDX-License-Identifier: GPL-3.0-only
//
// Like the voice key (GlobalHotkey): a recorded key with ⌃ ⌥ ⌘ is a Carbon
// hot key while 在其他输入法下也能用 is on, given up while Settings records
// a shortcut; a modifier tap goes through GlobalHotkey's event tap. Without
// the hot key the controller handles the key while 二狗 is the input
// source. GlobalHotkey owns the one handler and tells the two ids apart.

import Carbon

final class EnglishHotKey {
    static let shared = EnglishHotKey()
    static let id: UInt32 = 2

    /// True while the 说中文出英文 shortcut is registered system-wide.
    private(set) var registered = false
    private var ref: EventHotKeyRef?
    private var current: Shortcut?

    private init() {}

    /// `allowed`: 在其他输入法下也能用 is on and no shortcut is being recorded.
    func apply(_ allowed: Bool) {
        let key = EnglishVoice.read()
        let wanted: Shortcut? = allowed && key?.isTap == false ? key : nil
        if wanted == current { return }
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        registered = false
        current = wanted
        guard let wanted else { return }
        GlobalHotkey.shared.installHotKeyHandler()
        var carbon: UInt32 = 0
        if wanted.modifiers & Shortcut.command != 0 { carbon |= UInt32(cmdKey) }
        if wanted.modifiers & Shortcut.shift != 0 { carbon |= UInt32(shiftKey) }
        if wanted.modifiers & Shortcut.option != 0 { carbon |= UInt32(optionKey) }
        if wanted.modifiers & Shortcut.control != 0 { carbon |= UInt32(controlKey) }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4552_474F), id: Self.id)      // 'ERGO'
        let status = RegisterEventHotKey(UInt32(wanted.keyCode), carbon, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        registered = status == noErr && ref != nil
        if !registered {
            current = nil             // tried again on the next apply (like GlobalHotkey, audit 0.7.0 L2)
            Log.speech.error("english voice key: could not register the hot key (\(status, privacy: .public))")
        }
    }
}
