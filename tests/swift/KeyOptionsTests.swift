// ergou-ime — the voice key, the 中英 switch key and the English-app list.
// SPDX-License-Identifier: GPL-3.0-only

let keyOptionsTests: [Test] = [
    ("shortcut: Right Option tap by its device bit", {
        let k = Shortcut.tap(61)
        expect(k.isDown(flags: 0x80000 | 0x40), true, "right bit set: down")
        expect(k.isDown(flags: 0x80000 | 0x20), false, "only the left one is held: not ours")
        expect(k.isDown(flags: 0), false, "nothing held: up")
        expect(k.isDown(flags: 0x80000 | 0x40 | 0x20), true, "both held: ours is down")
        expect(Shortcut.tap(58).isDown(flags: 0x80000 | 0x20), true, "Left Option is its own key")
        expect(Shortcut.tap(58).isDown(flags: 0x80000 | 0x40), false, "and is not the right one")
    }),
    ("shortcut: no device bits and the flag set cannot be told", {
        // Events reaching an input method may carry no device bits; the
        // controller then alternates press / release.
        expect(Shortcut.tap(61).isDown(flags: 0x80000), nil, "Option flag alone")
        expect(Shortcut.tap(54).isDown(flags: 0x100000), nil, "Command flag alone")
        expect(Shortcut.tap(62).isDown(flags: 0x40000), nil, "Control flag alone")
    }),
    ("shortcut: Command, Control, Fn taps", {
        expect(Shortcut.tap(54).isDown(flags: 0x100000 | 0x10), true, "right Command")
        expect(Shortcut.tap(54).isDown(flags: 0x100000 | 0x08), false, "left Command")
        expect(Shortcut.tap(62).isDown(flags: 0x40000 | 0x2000), true, "right Control")
        expect(Shortcut.tap(62).isDown(flags: 0x40000 | 0x01), false, "left Control")
        expect(Shortcut.tap(54).isDown(flags: 0x80000 | 0x40), false, "Right Option is not Right Command")
        expect(Shortcut.tap(63).isDown(flags: 0x800000), true, "Fn down")
        expect(Shortcut.tap(63).isDown(flags: 0x80000 | 0x40), false, "Option is not Fn")
    }),
    ("shortcut: what can be one", {
        check(Shortcut.tap(61).isValid && Shortcut.tap(56).isValid && Shortcut.tap(63).isValid, "modifier taps")
        check(!Shortcut.tap(57).isValid, "Caps Lock is not a tap key")
        check(!Shortcut.tap(0).isValid, "a letter cannot be tapped")
        let space = Shortcut(keyCode: 49, modifiers: Shortcut.control, isTap: false, label: "Space")
        check(space.isValid, "⌃Space")
        check(!Shortcut(keyCode: 0, modifiers: 0, isTap: false, label: "A").isValid, "a plain letter is typing")
        check(!Shortcut(keyCode: 0, modifiers: Shortcut.shift, isTap: false, label: "A").isValid, "Shift + letter is typing")
        check(Shortcut(keyCode: 96, modifiers: 0, isTap: false, label: "F5").isValid, "a function key alone")
        check(!Shortcut(keyCode: 61, modifiers: Shortcut.control, isTap: false, label: "x").isValid, "a modifier is not the key of a combination")
        check(!Shortcut(keyCode: 49, modifiers: 0x800000, isTap: false, label: "Space").isValid, "unknown modifier bits")
        check(!Shortcut(keyCode: 49, modifiers: Shortcut.control, isTap: false, label: "").isValid, "needs a label")
        check(!Shortcut(keyCode: 49, modifiers: Shortcut.control, isTap: false, label: "a:b").isValid, "no colon in the label")
    }),
    ("shortcut: stored and read back", {
        let space = Shortcut(keyCode: 49, modifiers: Shortcut.control | Shortcut.option, isTap: false, label: "Space")
        expect(space.stored, "key:49:786432:Space", "combination")
        expect(Shortcut(stored: space.stored), space, "round trip")
        expect(Shortcut(stored: "tap:61"), .tap(61), "tap")
        expect(space.title, "⌃⌥Space", "title")
        expect(Shortcut.tap(60).title, "右 Shift", "tap title")
        for bad in ["", "tap:57", "tap:x", "key:0:0:A", "key:49:786432:", "key:49:786432:a\nb", "tap:61:1", "junk",
                    "key:300:262144:X", "key:49:99999999999999999999:Space"] {
            check(Shortcut(stored: bad) == nil, "rejected: \(bad.debugDescription)")
        }
        check(Shortcut(stored: nil) == nil, "nothing stored")
    }),
    ("shortcut: matching a key press", {
        let s = Shortcut(keyCode: 49, modifiers: Shortcut.control, isTap: false, label: "Space")
        check(s.matches(keyCode: 49, flags: Shortcut.control), "exact")
        check(s.matches(keyCode: 49, flags: Shortcut.control | 0x01 | 0x100), "device bits do not matter")
        check(!s.matches(keyCode: 49, flags: Shortcut.control | Shortcut.shift), "an extra modifier is another key")
        check(!s.matches(keyCode: 49, flags: 0), "the plain key")
        check(!s.matches(keyCode: 48, flags: Shortcut.control), "another key")
        check(!Shortcut.tap(61).matches(keyCode: 61, flags: 0x80000), "a tap is not a key press")
    }),
    ("shortcut: conflicts and which Shift librime listens to", {
        check(Shortcut.tap(61).conflicts(with: .tap(61)), "same tap")
        check(!Shortcut.tap(61).conflicts(with: .tap(58)), "left and right are different keys")
        var s = Shortcuts()
        check(s.leftShiftSwitches && s.rightShiftSwitches, "default: either Shift")
        s.ascii = .tap(Shortcut.leftShift)
        check(s.leftShiftSwitches && !s.rightShiftSwitches, "left only")
        s.ascii = .tap(Shortcut.rightShift)
        check(!s.leftShiftSwitches && s.rightShiftSwitches, "right only")
        s.ascii = .tap(62)
        check(!s.leftShiftSwitches && !s.rightShiftSwitches, "another key: librime leaves both Shifts alone")
        expect(Shortcuts().voice, .tap(61), "voice: Right Option by default")
    }),
    ("english apps: nothing stored means the defaults", {
        expect(EnglishApps.list(nil), EnglishApps.defaults, "not set")
        expect(EnglishApps.list("com.apple.Terminal"), EnglishApps.defaults, "not a list")
        expect(EnglishApps.list([String]()), [], "an empty list is the user's choice")
        check(EnglishApps.defaults.allSatisfy(EnglishApps.isValid), "every default is valid")
        check(EnglishApps.defaults.contains("com.apple.Terminal") && EnglishApps.defaults.contains("com.microsoft.VSCode"),
              "terminals and VS Code")
        expect(EnglishApps.legacy.count, 6, "the six terminals of before")
        check(!EnglishApps.legacy.contains("com.microsoft.VSCode"), "legacy has no editors")
    }),
    ("english apps: only bundle identifiers survive", {
        let raw = ["com.example.App", "com.example.App", "bad id", "a/b", "", "x: y\n- z", "名字", "org.ok_1-2",
                   String(repeating: "a", count: 156)]
        expect(EnglishApps.list(raw), ["com.example.App", "org.ok_1-2"], "valid, distinct, in order")
        expect(EnglishApps.list((0..<300).map { "com.example.a\($0)" }).count, EnglishApps.maxCount, "capped")
    }),
    ("english apps: added and removed apps start over", {
        expect(EnglishApps.changed(from: ["a", "b"], to: ["b", "c"]), ["a", "c"], "a removed, c added")
        expect(EnglishApps.changed(from: ["a", "b"], to: ["b", "a"]), [], "order alone changes nothing")
    }),
    ("panel layout: horizontal unless chosen", {
        expect(PanelStyle().layout, .horizontal, "default")
        expect(PanelLayout(rawValue: "vertical"), .vertical, "raw value")
        check(PanelLayout(rawValue: "diagonal") == nil, "unknown value is dropped")
    }),
]
