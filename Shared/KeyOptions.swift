// ergou-ime — keys the user can change, apps that start in English, and
// the small typing options added with them (设置 › 输入).
// SPDX-License-Identifier: GPL-3.0-only
//
// Like every shared setting, these are written by Settings and read by the
// input method, which trusts none of it: enums fall back to their default,
// the app list keeps only strings that look like bundle identifiers.

import Foundation

// MARK: - 快捷键

/// A key the user recorded in Settings: either one modifier key tapped on
/// its own (Right Option, Left Shift, Fn …) or a key pressed with
/// modifiers (⌃Space, ⌥⌘V, F5).
struct Shortcut: Equatable {
    /// Virtual key code. For a tap: the modifier key itself.
    var keyCode: UInt16
    /// Shift / Control / Option / Command (NSEvent flag bits) held with
    /// the key. 0 for a tap.
    var modifiers: UInt = 0
    var isTap: Bool
    /// What the key prints, for display only ("Space", "V", "F5").
    var label = ""

    static let shift: UInt = 0x20000, control: UInt = 0x40000, option: UInt = 0x80000, command: UInt = 0x100000
    static let modifierMask = shift | control | option | command

    static func tap(_ keyCode: UInt16) -> Shortcut { Shortcut(keyCode: keyCode, isTap: true) }

    /// The modifier keys that can be tapped: name, the event-flag bit that
    /// is set only while THIS key is down (NX_DEVICE…KEYMASK), the same
    /// for its twin on the other side, and the device-independent flag.
    /// Fn has no twin. Caps Lock is left out: it is a switch, not a key
    /// you tap.
    static let modifierKeys: [UInt16: (name: String, bit: UInt?, twin: UInt?, flag: UInt)] = [
        56: ("左 Shift", 0x02, 0x04, shift), 60: ("右 Shift", 0x04, 0x02, shift),
        59: ("左 Control", 0x01, 0x2000, control), 62: ("右 Control", 0x2000, 0x01, control),
        58: ("左 Option", 0x20, 0x40, option), 61: ("右 Option", 0x40, 0x20, option),
        55: ("左 Command", 0x08, 0x10, command), 54: ("右 Command", 0x10, 0x08, command),
        63: ("Fn（地球键）", nil, nil, 0x800000),
    ]
    /// Every modifier key code, Caps Lock included.
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    /// F1–F20: may be used without a modifier.
    static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                                            105, 107, 113, 106, 64, 79, 80, 90]
    static let leftShift: UInt16 = 56, rightShift: UInt16 = 60, rightOption: UInt16 = 61, fn: UInt16 = 63

    var isValid: Bool {
        if isTap { return modifiers == 0 && Shortcut.modifierKeys[keyCode] != nil }
        guard keyCode <= 127, !Shortcut.modifierKeyCodes.contains(keyCode),
              modifiers & ~Shortcut.modifierMask == 0,
              (1...12).contains(label.count),
              !label.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0 == ":" })
        else { return false }
        // A plain key or Shift + key is typing, not a shortcut.
        return modifiers & (Shortcut.control | Shortcut.option | Shortcut.command) != 0
            || Shortcut.functionKeys.contains(keyCode)
    }

    var title: String {
        if isTap { return Shortcut.modifierKeys[keyCode]?.name ?? "?" }
        var s = ""
        if modifiers & Shortcut.control != 0 { s += "⌃" }
        if modifiers & Shortcut.option != 0 { s += "⌥" }
        if modifiers & Shortcut.shift != 0 { s += "⇧" }
        if modifiers & Shortcut.command != 0 { s += "⌘" }
        return s + label
    }

    /// "tap:61" or "key:<code>:<modifiers>:<label>".
    var stored: String {
        isTap ? "tap:\(keyCode)" : "key:\(keyCode):\(modifiers):\(label)"
    }

    /// nil for anything that is not a valid stored shortcut.
    init?(stored: String?) {
        guard let stored else { return nil }
        let parts = stored.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2, parts[0] == "tap", let code = UInt16(parts[1]) {
            self.init(keyCode: code, isTap: true)
        } else if parts.count == 4, parts[0] == "key", let code = UInt16(parts[1]), let mods = UInt(parts[2]) {
            self.init(keyCode: code, modifiers: mods, isTap: false, label: parts[3])
        } else {
            return nil
        }
        guard isValid else { return nil }
    }

    init(keyCode: UInt16, modifiers: UInt = 0, isTap: Bool, label: String = "") {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isTap = isTap
        self.label = label
    }

    /// For a tap: is the key down, from the flags of ITS flagsChanged
    /// event? nil when the flags cannot tell (no device bits and the plain
    /// flag is set: it may be the twin on the other side that is held).
    func isDown(flags raw: UInt) -> Bool? {
        guard let key = Shortcut.modifierKeys[keyCode] else { return false }
        guard let bit = key.bit, let twin = key.twin else { return raw & key.flag != 0 }
        if raw & bit != 0 { return true }
        if raw & twin != 0 || raw & key.flag == 0 { return false }
        return nil
    }

    /// Is a key-down event with this key code and these flags the shortcut?
    func matches(keyCode code: UInt16, flags raw: UInt) -> Bool {
        !isTap && code == keyCode && raw & Shortcut.modifierMask == modifiers
    }

    /// Would the two fire on the same key? (Same key, or the same modifier
    /// key tapped.)
    func conflicts(with other: Shortcut) -> Bool {
        isTap == other.isTap && keyCode == other.keyCode && modifiers == other.modifiers
    }
}

/// The two shortcuts as saved, read from the shared settings at most twice
/// a second: the input method asks on every key.
struct Shortcuts: Equatable {
    /// Tap to start and stop speaking. Default: Right Option.
    var voice = Shortcut.tap(Shortcut.rightOption)
    /// Switches 中/英. nil: the default, either Shift (librime's own
    /// handling: left keeps the typed letters, right types the first
    /// candidate).
    var ascii: Shortcut?

    /// librime handles a Shift tap; anything else the input method does.
    var leftShiftSwitches: Bool { ascii == nil || ascii == .tap(Shortcut.leftShift) }
    var rightShiftSwitches: Bool { ascii == nil || ascii == .tap(Shortcut.rightShift) }

    static var current: Shortcuts {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached, now - cached.at < 0.5 { return cached.value }
        let value = read()
        cached = (value, now)
        return value
    }

    /// Without the cache (Settings, right after saving).
    static func read() -> Shortcuts {
        let defaults = Paths.sharedDefaults
        var value = Shortcuts()
        if let voice = Shortcut(stored: defaults.string(forKey: SettingKey.voiceShortcut)) { value.voice = voice }
        value.ascii = Shortcut(stored: defaults.string(forKey: SettingKey.asciiShortcut))
        // Both on one key cannot work; the voice key gives way to its default.
        if value.voice.conflicts(with: value.ascii ?? .tap(Shortcut.leftShift))
            || (value.ascii == nil && value.voice == .tap(Shortcut.rightShift)) {
            value.voice = .tap(Shortcut.rightOption)
        }
        return value
    }

    private static var cached: (value: Shortcuts, at: TimeInterval)?
}

extension SettingKey {
    /// String, Shortcut.stored: switches 中/英. Not set: either Shift.
    static let asciiShortcut = "asciiShortcut"
    /// String, Shortcut.stored: starts and stops voice. Not set: Right Option.
    static let voiceShortcut = "voiceShortcut"
    /// Bool, emoji and symbols after the word that names them. Not set:
    /// on with 拼音, off with 五笔拼音混输 (SharedSettings.emojiCandidates).
    static let emojiCandidates = "emojiCandidates"
    /// Bool, 以词定字 with [ and ], default true.
    static let selectCharacter = "selectCharacter"
    /// [String], bundle identifiers of apps that start in English. Not
    /// set: EnglishApps.defaults.
    static let englishApps = "englishApps"
}

extension SharedSettings {
    /// An emoji takes a place in the candidate row and moves what follows
    /// it. With pinyin that is what people expect; 五笔 is typed by
    /// position, so there it is off until the user turns it on.
    static var emojiCandidates: Bool {
        Paths.sharedDefaults.object(forKey: SettingKey.emojiCandidates) as? Bool ?? (inputScheme == .pinyin)
    }

    static var selectCharacter: Bool {
        Paths.sharedDefaults.object(forKey: SettingKey.selectCharacter) as? Bool ?? true
    }

    static var englishApps: [String] {
        EnglishApps.list(Paths.sharedDefaults.object(forKey: SettingKey.englishApps))
    }

    static func saveEnglishApps(_ ids: [String]) {
        Paths.sharedDefaults.set(EnglishApps.list(ids), forKey: SettingKey.englishApps)
    }
}

extension SharedNotifications {
    /// Settings is recording a shortcut: the keys pressed there are for the
    /// recorder, so the input method must not start voice on them (pressing
    /// the old voice key as part of a new shortcut started a recording, D
    /// 2026-11-12). Posted when recording starts and every few seconds
    /// while it lasts; the input method stands down for
    /// `shortcutRecordingHold` after each one, so a Settings that quits or
    /// crashes cannot leave voice off. Anyone can post it: the worst it
    /// does is that hold.
    static let shortcutRecordingBegan = "com.codamon.ergou.shortcut-recording-began"
    static let shortcutRecordingEnded = "com.codamon.ergou.shortcut-recording-ended"
    static let shortcutRecordingHold: TimeInterval = 8
}

// MARK: - 默认用英文的应用

/// Apps whose text fields start in English: terminals and code editors.
/// The input method still remembers, per app, what the user last switched
/// to; the list decides where an app starts, and adding or removing an app
/// here makes it start over (ErgouInputController).
enum EnglishApps {
    static let defaults = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "io.alacritty",
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
        "com.todesktop.230313mzl4w4u92",          // Cursor
        "dev.zed.Zed",
    ]
    /// What to call a default app that is not installed (Settings).
    static let names = [
        "com.apple.Terminal": "终端", "com.googlecode.iterm2": "iTerm", "dev.warp.Warp-Stable": "Warp",
        "com.mitchellh.ghostty": "Ghostty", "net.kovidgoyal.kitty": "kitty", "io.alacritty": "Alacritty",
        "com.microsoft.VSCode": "Visual Studio Code", "com.microsoft.VSCodeInsiders": "VS Code Insiders",
        "com.vscodium": "VSCodium", "com.todesktop.230313mzl4w4u92": "Cursor", "dev.zed.Zed": "Zed",
    ]

    /// The list before it could be edited (terminals only), for installs
    /// that update: see ErgouInputController.syncEnglishApps.
    static let legacy = Array(defaults.prefix(6))

    static let maxCount = 200

    /// A bundle identifier: letters, digits, dots, hyphens and underscores.
    static func isValid(_ id: String) -> Bool {
        (1...155).contains(id.utf8.count) && id.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
                || $0 == "." || $0 == "-" || $0 == "_"
        }
    }

    /// nil or not a list: the defaults. Otherwise the valid, distinct
    /// entries in their order (an empty list is the user's choice).
    static func list(_ raw: Any?) -> [String] {
        guard let raw = raw as? [String] else { return defaults }
        var seen = Set<String>()
        return Array(raw.filter { isValid($0) && seen.insert($0).inserted }.prefix(maxCount))
    }

    /// Apps whose remembered 中/英 should be forgotten after the list
    /// changed from `old` to `new`: the ones added or removed.
    static func changed(from old: [String], to new: [String]) -> Set<String> {
        Set(old).symmetricDifference(new)
    }
}
