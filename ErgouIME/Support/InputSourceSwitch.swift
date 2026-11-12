// ergou-ime — "I switched to 二狗, so I want Chinese".
// SPDX-License-Identifier: GPL-3.0-only
//
// 中/英 (Shift) is remembered per app. A user who presses Shift for English,
// then switches to another input source for more English, and switches back
// to 二狗 to type Chinese, still got English and had to press Shift again
// (user report, 2026-11-12). Switching the input source to 二狗 now always
// starts in Chinese.
//
// One exception: a password field makes macOS switch to an ASCII source by
// itself and back afterwards. That return is not the user asking for
// Chinese (in a terminal, after a sudo password, English must stay), so a
// switch away while secure input is on does not count.

import Foundation

/// The rule, without the system calls (tests/swift/InputSourceSwitchTests.swift).
struct InputSourceSwitch {
    private(set) var oursSelected: Bool
    private var leftForSecureInput = false

    init(oursSelected: Bool) { self.oursSelected = oursSelected }

    /// Call when the selected input source changed. True: the user switched
    /// to 二狗 from another source — start in Chinese.
    mutating func changed(toOurs: Bool, secureInput: Bool) -> Bool {
        defer { oursSelected = toOurs }
        if oursSelected, !toOurs {
            leftForSecureInput = secureInput
            return false
        }
        guard !oursSelected, toOurs else { return false }
        let bySystem = leftForSecureInput
        leftForSecureInput = false
        return !bySystem
    }
}
