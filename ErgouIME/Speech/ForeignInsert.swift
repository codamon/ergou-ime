// ergou-ime — type a voice result while another input source is active (M3 T3.3).
// SPDX-License-Identifier: GPL-3.0-only
//
// Only our controller can insert text, and only while our input source is
// selected. So: remember the current source, select ours, wait for macOS to
// activate our controller on the focused text field, insert, and select the
// previous source again. If no controller shows up in time there is no text
// field (T3.4) and the caller falls back to the clipboard.

import Carbon
import Foundation

enum ForeignInsert {
    static func insert(_ text: String, done: @escaping (Bool) -> Void) {
        guard let previous = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ours = ourSource() else { done(false); return }
        // Our own switch in and back is not the user asking for Chinese.
        InputSourceWatcher.shared.ignoreChanges(for: 1.5)
        guard TISSelectInputSource(ours) == noErr else {
            Log.speech.error("global voice: could not select our input source")
            done(false)
            return
        }
        waitForTarget(deadline: ProcessInfo.processInfo.systemUptime + 0.5) { target in
            let ok = target?.insertVoiceText(text, applied: [], track: false) ?? false
            // Give the client a moment to take the text before switching back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                TISSelectInputSource(previous)
            }
            Log.speech.notice("global voice: inserted via input source switch: \(ok, privacy: .public)")
            done(ok)
        }
    }

    private static func waitForTarget(deadline: TimeInterval, _ found: @escaping (VoiceTarget?) -> Void) {
        if let target = VoiceSession.shared.target { found(target); return }
        guard ProcessInfo.processInfo.systemUptime < deadline else { found(nil); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { waitForTarget(deadline: deadline, found) }
    }

    private static func ourSource() -> TISInputSource? {
        for id in InputSourceRegistrar.inputModeIDs {
            let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
            if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
               let first = list.first { return first }
        }
        return nil
    }
}
