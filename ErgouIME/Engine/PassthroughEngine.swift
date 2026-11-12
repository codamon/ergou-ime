// ergou-ime — passthrough engine (first milestone).
// SPDX-License-Identifier: GPL-3.0-only
//
// Commits printable ASCII straight to the client. Anything with Command,
// Control or Option, and all non-printing keys (arrows, Return, Delete …), is left to
// the application so shortcuts and editing keep working.

import AppKit

final class PassthroughEngine: InputEngine {
    var asciiMode: Bool = true

    func handle(_ key: KeyInput) -> EngineState? {
        guard key.phase == .down else { return nil }
        // Option is excluded too: Option+key produces accents/symbols that the
        // app's own key handling gets right (dead keys etc.).
        if !key.modifiers.intersection([.command, .control, .option]).isEmpty { return nil }
        guard key.characters.count == 1,
              let scalar = key.characters.unicodeScalars.first,
              scalar.isASCII, (0x20...0x7E).contains(scalar.value)
        else { return nil }
        return EngineState(commitText: key.characters, asciiMode: true)
    }

    func selectCandidate(at index: Int) -> EngineState? { nil }
    func changePage(backward: Bool) -> EngineState? { nil }

    func reset() {}

    func takeRawInput() -> String? { nil }
    func option(_ name: String) -> Bool { false }
    func setOption(_ name: String, _ on: Bool) {}
    func candidates(from index: Int, max: Int) -> [Candidate] { [] }
    func selectAbsolute(_ index: Int) -> EngineState? { nil }
}
