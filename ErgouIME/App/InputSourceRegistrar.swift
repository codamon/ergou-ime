// ergou-ime — register / enable the input source with macOS.
// SPDX-License-Identifier: GPL-3.0-only

import Carbon
import Foundation

enum InputSourceRegistrar {
    /// Input mode IDs from Info.plist → ComponentInputModeDict. Hard-coded there
    /// too, because Xcode does not expand build settings in plist keys.
    static let inputModeIDs = ["com.codamon.inputmethod.Ergou.Wubi"]

    static func register(bundleURL: URL) -> Bool {
        let status = TISRegisterInputSource(bundleURL as CFURL)
        if status != noErr {
            Log.app.error("TISRegisterInputSource failed: \(status)")
        }
        return status == noErr
    }

    static func enableAndSelect() -> Bool { enable(select: true) }

    /// `--list-input-sources`: what Text Input Sources has for this input
    /// method, for bug reports (a user saw 14 rows of 二狗 in System Settings
    /// after every install; scripts/repair-input-sources.sh prints this).
    /// IDs, kinds and flags only.
    static func listSources() {
        let all = (TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
        func text(_ source: TISInputSource, _ key: CFString) -> String {
            guard let raw = TISGetInputSourceProperty(source, key) else { return "-" }
            return "\(Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue())"
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.codamon.inputmethod.Ergou"
        var mine = 0, enabledTotal = 0
        for source in all {
            if text(source, kTISPropertyInputSourceIsEnabled) == "1" { enabledTotal += 1 }
            let id = text(source, kTISPropertyInputSourceID)
            guard id.hasPrefix(bundleID) || text(source, kTISPropertyBundleID) == bundleID else { continue }
            mine += 1
            print("\(id) | \(text(source, kTISPropertyInputSourceType)) | enabled \(text(source, kTISPropertyInputSourceIsEnabled))"
                  + " | selectable \(text(source, kTISPropertyInputSourceIsSelectCapable))"
                  + " | selected \(text(source, kTISPropertyInputSourceIsSelected))"
                  + " | \(text(source, kTISPropertyLocalizedName))")
        }
        print("二狗的输入源：\(mine) 个（正常是 2 个：输入法本身 + 1 个输入模式）；系统里共 \(all.count) 个输入源，已启用 \(enabledTotal) 个")
    }

    /// Enables the bundle's own source and every input mode; selects the
    /// modes too when `select` (scripts/install.sh, first install by hand).
    /// The .pkg postinstall enables without selecting (scripts/pkg/input-sources.sh).
    static func enable(select: Bool) -> Bool {
        var found = false
        let bundleID = Bundle.main.bundleIdentifier ?? "com.codamon.inputmethod.Ergou"
        for id in [bundleID] + inputModeIDs {
            let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
            guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else {
                continue
            }
            for source in list {
                found = true
                // Only when not enabled yet. On macOS 27, enabling a
                // third-party input source that is ALREADY enabled opens
                // System Settings › Keyboard, so every update brought that
                // window up (D, 2026-11-12; reproduced with
                // --enable-input-source-only, --register-input-source alone
                // does not).
                if !isEnabled(source) { TISEnableInputSource(source) }
                if select && id != bundleID { TISSelectInputSource(source) }
            }
        }
        if !found {
            Log.app.error("Input source not found; run --register-input-source first, then log out and in if needed")
        }
        return found
    }

    private static func isEnabled(_ source: TISInputSource) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }
}
