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
                TISEnableInputSource(source)
                if select && id != bundleID { TISSelectInputSource(source) }
            }
        }
        if !found {
            Log.app.error("Input source not found; run --register-input-source first, then log out and in if needed")
        }
        return found
    }
}
