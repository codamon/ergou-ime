// ergou-ime — 麦克风 items in the input menu (same choice as Settings › 语音).
// SPDX-License-Identifier: GPL-3.0-only
//
// Flat items, not a submenu: input-menu submenus did not deliver their
// actions on D's Mac (2026-11-10).

import AppKit
import InputMethodKit

/// UIDs behind the 麦克风 items of the menu last built, by tag. Tags,
/// not representedObject: the item IMK hands back may be a copy.
private var menuMicrophones: [Int: String] = [:]
private let microphoneTagBase = 1000

extension ErgouInputController {
    /// IMK calls menu actions with a dictionary holding the item under
    /// kIMKCommandMenuItemName; plain AppKit passes the item itself.
    static func menuItem(from sender: Any?) -> NSMenuItem? {
        if let item = sender as? NSMenuItem { return item }
        if let info = sender as? [AnyHashable: Any] { return info[kIMKCommandMenuItemName] as? NSMenuItem }
        return nil
    }

    func addMicrophoneItems(to menu: NSMenu) {
        let chosen = SharedSettings.microphoneUID
        let inputs = AudioInputs.all()
        menu.addItem(.separator())
        let header = menu.addItem(withTitle: "麦克风", action: nil, keyEquivalent: "")
        header.isEnabled = false

        let auto = menu.addItem(withTitle: "自动", action: #selector(chooseMicrophone(_:)), keyEquivalent: "")
        menuMicrophones = [microphoneTagBase: ""]
        auto.tag = microphoneTagBase
        auto.target = self
        auto.indentationLevel = 1
        auto.state = chosen.isEmpty ? .on : .off
        for (i, input) in inputs.enumerated() {
            let row = menu.addItem(withTitle: input.name, action: #selector(chooseMicrophone(_:)), keyEquivalent: "")
            row.tag = microphoneTagBase + 1 + i
            menuMicrophones[row.tag] = input.uid
            row.target = self
            row.indentationLevel = 1
            row.state = input.uid == chosen ? .on : .off
        }
        if !chosen.isEmpty, !inputs.contains(where: { $0.uid == chosen }) {
            let name = Paths.sharedDefaults.string(forKey: SettingKey.microphoneName) ?? ""
            let missing = menu.addItem(withTitle: "\(name.isEmpty ? "之前选的麦克风" : name)（未连接）",
                                       action: nil, keyEquivalent: "")
            missing.indentationLevel = 1
            missing.state = .on
            missing.isEnabled = false
        }
    }

    @objc func chooseMicrophone(_ sender: Any?) {
        Log.speech.notice("microphone menu: sender \(String(describing: type(of: sender)), privacy: .public), tag \(Self.menuItem(from: sender)?.tag ?? -1, privacy: .public)")
        guard let tag = Self.menuItem(from: sender)?.tag, let uid = menuMicrophones[tag] else { return }
        SharedSettings.chooseMicrophone(AudioInputs.all().first { $0.uid == uid })
    }
}
