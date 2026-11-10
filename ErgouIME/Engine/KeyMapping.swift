// ergou-ime — macOS key events → X11 keysyms (what librime expects).
// SPDX-License-Identifier: GPL-3.0-only
//
// Minimal table for the first milestone. Squirrel has a complete mapping in
// its macos_keycode file; if we copy from it, keep its copyright header.

import AppKit
import Carbon.HIToolbox

enum KeyMapping {
    // X11 modifier masks (librime uses the same bits).
    static let shiftMask: Int32 = 1 << 0
    static let lockMask: Int32 = 1 << 1
    static let controlMask: Int32 = 1 << 2
    static let mod1Mask: Int32 = 1 << 3 // Alt / Option
    static let superMask: Int32 = 1 << 26 // Command
    static let releaseMask: Int32 = 1 << 30

    private static let specialKeys: [Int: Int32] = [
        kVK_Return: 0xFF0D, kVK_ANSI_KeypadEnter: 0xFF8D,
        kVK_Tab: 0xFF09, kVK_Space: 0x0020,
        kVK_Delete: 0xFF08, kVK_ForwardDelete: 0xFFFF,
        kVK_Escape: 0xFF1B,
        kVK_LeftArrow: 0xFF51, kVK_UpArrow: 0xFF52,
        kVK_RightArrow: 0xFF53, kVK_DownArrow: 0xFF54,
        kVK_PageUp: 0xFF55, kVK_PageDown: 0xFF56,
        kVK_Home: 0xFF50, kVK_End: 0xFF57,
        kVK_Shift: 0xFFE1, kVK_RightShift: 0xFFE2,
        kVK_Control: 0xFFE3, kVK_RightControl: 0xFFE4,
        kVK_Option: 0xFFE9, kVK_RightOption: 0xFFEA,
        kVK_Command: 0xFFEB, kVK_RightCommand: 0xFFEC,
        kVK_CapsLock: 0xFFE5,
    ]

    /// X11 keysym for the key, or nil if we do not know it yet.
    static func keysym(for key: KeyInput) -> Int32? {
        if let special = specialKeys[Int(key.keyCode)] { return special }
        // Printable ASCII: keysym == code point.
        if key.characters.count == 1, let c = key.characters.first,
           let s = c.unicodeScalars.first, (0x20...0x7E).contains(s.value) {
            // librime, like X11, has separate keysyms for a and A, but
            // charactersIgnoringModifiers gives "a" for Shift+A. Without this,
            // Shift+letter could not type capitals (D, 2026-11-09). Same rule
            // as Squirrel (sources/MacOSKeyCodes.swift).
            let shift = key.modifiers.contains(.shift)
            let caps = key.modifiers.contains(.capsLock)
            if c.isLowercase, shift != caps, let upper = c.uppercased().unicodeScalars.first {
                return Int32(upper.value)
            }
            return Int32(s.value)
        }
        return nil
    }

    static func mask(for key: KeyInput) -> Int32 {
        var mask: Int32 = 0
        if key.modifiers.contains(.shift) { mask |= shiftMask }
        if key.modifiers.contains(.capsLock) { mask |= lockMask }
        if key.modifiers.contains(.control) { mask |= controlMask }
        if key.modifiers.contains(.option) { mask |= mod1Mask }
        if key.modifiers.contains(.command) { mask |= superMask }
        if key.phase == .up { mask |= releaseMask }
        return mask
    }
}
