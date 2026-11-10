// ergou-ime — IMKInputController subclass.
// SPDX-License-Identifier: GPL-3.0-only
//
// macOS creates one controller per client (text field / document) that uses
// this input method. The controller translates NSEvents into KeyInput, hands
// them to an InputEngine and applies the resulting EngineState to the client:
// commit text, marked text (preedit) and the candidate panel.
//
// M0: with the passthrough engine every printable ASCII key is committed
// directly. Once built with librime (ERGOU_WITH_RIME) the same code path
// drives Wubi input (M1).
//
// Voice results (M2/M3) are NOT inserted directly: they become candidates in
// the candidate panel — Enter commits, Esc cancels, digits pick another
// candidate. Only the global "no text field" path (M3) bypasses the panel.
//
// Privacy: key content is never logged, stored or sent anywhere. The class
// name must match InputMethodServerControllerClass in Info.plist.

import AppKit
import Carbon.HIToolbox
import InputMethodKit

final class ErgouInputController: IMKInputController, VoiceTarget {
    private lazy var engine: InputEngine = EngineHost.shared.makeEngine()
    private var hasMarkedText = false

    private static let noReplacement = NSRange(location: NSNotFound, length: 0)

    // MARK: - Events

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput else { return false }

        switch event.type {
        case .keyDown:
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = KeyInput(
                keyCode: event.keyCode,
                characters: Self.keyCharacters(event, modifiers: modifiers),
                modifiers: modifiers)
            // Password fields: macOS normally switches non-Roman input methods
            // away. If we still get keys, stay out of the way (Privacy rule 6).
            if SecureInput.isActive { return false }
            // A key while Right Option is down makes it a shortcut, not a tap.
            VoiceSession.shared.keyPressed()
            if VoiceSession.shared.isActive, event.keyCode == UInt16(kVK_Escape) {
                VoiceSession.shared.cancel()
                return true
            }
            // Return while tidying: skip the tidy-up, type what was recognised.
            if VoiceSession.shared.isTidying,
               event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                VoiceSession.shared.skipTidy()
                return true
            }
            if let handled = handlePredictionKey(event, client: client) { return handled }
            if let handled = handleGridKey(event, client: client) { return handled }
            var timing = KeyTiming()
            defer { timing.log() }
            guard let state = timing.measure(\.engine, { engine.handle(key) }) else { return false }
            apply(state, to: client, timing: &timing)
            return state.consumedKey

        case .flagsChanged:
            // Never consume modifier events: Fn, Option etc. must reach the
            // system and the app unchanged. We only watch Right Option.
            // From M3 the global listen-only CGEventTap (T3.2) is the single
            // detector and this path forwards to it.
            if event.keyCode == UInt16(kVK_Shift) || event.keyCode == UInt16(kVK_RightShift) {
                // librime's ascii_composer does the Shift tap (default.yaml:
                // Shift_L inline_ascii, Shift_R commit_text); it only needs
                // to see the press and the release.
                VoiceSession.shared.keyPressed()
                resetTransientUI()
                // Device bit when present (NX_DEVICE{L,R}SHIFTKEYMASK), else the Shift flag.
                let bit: UInt = event.keyCode == UInt16(kVK_Shift) ? 0x02 : 0x04
                let raw = event.modifierFlags.rawValue
                let down = raw & 0x06 != 0 ? raw & bit != 0 : event.modifierFlags.contains(.shift)
                let before = engine.asciiMode
                let key = KeyInput(keyCode: event.keyCode, characters: "",
                                   modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                                   phase: down ? .down : .up)
                if let state = engine.handle(key) { apply(state, to: client) }
                if !down, engine.asciiMode != before {
                    CandidatePanel.shared.flash(engine.asciiMode ? "英" : "中", caretRect: caretRect(in: client))
                    rememberAsciiMode(for: client)
                }
                return false
            }
            if event.keyCode == Self.rightOptionKeyCode, GlobalHotkey.shared.isRunning {
                // The global tap sees this press too and is the only detector.
                currentClient = client as AnyObject
                VoiceSession.shared.target = self
            } else if event.keyCode == Self.rightOptionKeyCode {
                currentClient = client as AnyObject
                VoiceSession.shared.target = self
                // Prefer the device bits (NX_DEVICERALTKEYMASK 0x40, left 0x20)
                // so holding Left Option does not count — but events reaching
                // an input method may carry no device bits at all (voice broke
                // when we required 0x40, D's Mac 2026-11-09); then fall back
                // to the plain Option flag.
                // Without device bits, a Right Option event with the Option
                // flag still set is ambiguous: Left Option may be held. Then
                // the events of key 61 alternate press / release. The state
                // is shared: the release may reach another controller.
                let raw = event.modifierFlags.rawValue
                let rightBit = raw & 0x40 != 0, leftBit = raw & 0x20 != 0
                let rightDown: Bool
                if rightBit {
                    rightDown = true
                } else if leftBit || !event.modifierFlags.contains(.option) {
                    rightDown = false
                } else {
                    rightDown = !Self.rightOptionIsDown
                }
                Self.rightOptionIsDown = rightDown
                if rightDown {
                    VoiceSession.shared.rightOptionDown()
                } else {
                    VoiceSession.shared.rightOptionUp()
                }
            } else {
                // Another modifier while Right Option is down: not a tap.
                VoiceSession.shared.keyPressed()
            }
            return false

        default:
            return false
        }
    }

    /// The character librime should see. charactersIgnoringModifiers drops
    /// Shift for punctuation on macOS (Shift+/ gives "/", not "?"), so with
    /// only Shift/Caps Lock held and a non-letter we take `characters`.
    /// Same rule as Squirrel (sources/SquirrelInputController.swift).
    private static func keyCharacters(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> String {
        let plain = event.charactersIgnoringModifiers ?? ""
        let capitalOnly = modifiers.intersection([.shift, .capsLock, .control, .option, .command]).isSubset(of: [.shift, .capsLock])
        if let first = plain.first,
           (capitalOnly && !first.isLetter) || (!capitalOnly && !first.isASCII) {
            return event.characters ?? plain
        }
        return plain
    }

    // MARK: - Voice (M2)

    private static let rightOptionKeyCode: UInt16 = 61
    /// Last Right Option state we reported (see the flagsChanged handler).
    private static var rightOptionIsDown = false
    /// The client this controller is serving while active; nil when inactive.
    private weak var currentClient: AnyObject?

    // VoiceTarget
    var voiceCaretRect: NSRect {
        guard let client = currentClient as? IMKTextInput else { return .zero }
        return caretRect(in: client)
    }

    /// Up to `limit` characters before the cursor, for the cloud tidy-up
    /// (only when the user allows it; never in secure input).
    func voiceTextBeforeCursor(limit: Int) -> String? {
        guard !SecureInput.isActive, let client = currentClient as? IMKTextInput else { return nil }
        let selected = client.selectedRange()
        guard selected.location != NSNotFound, selected.location > 0 else { return nil }
        // UTF-16 units: ask for twice as many, then keep `limit` characters.
        let length = min(selected.location, limit * 2)
        let range = NSRange(location: selected.location - length, length: length)
        guard let text = client.attributedSubstring(from: range)?.string, !text.isEmpty else { return nil }
        return String(text.suffix(limit))
    }

    var voiceAppBundleID: String? { bundleID(currentClient) }

    func insertVoiceText(_ text: String) -> Bool {
        guard let client = currentClient as? IMKTextInput else { return false }
        if hasMarkedText { clearMarkedText(in: client); engine.reset() }
        resetTransientUI()
        CandidatePanel.shared.hide()
        client.insertText(spaced(text, in: client), replacementRange: Self.noReplacement)
        return true
    }

    // MARK: - 中/英 per app

    /// Apps where English is the better start (terminals).
    private static let englishFirst: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "io.alacritty",
    ]
    private static let asciiDefaultsKey = "asciiModeByApp"

    private func bundleID(_ client: Any?) -> String? {
        (client as? IMKTextInput)?.bundleIdentifier()
    }

    private func restoreAsciiMode(for client: Any?) {
        guard let id = bundleID(client) else { return }
        let saved = UserDefaults.standard.dictionary(forKey: Self.asciiDefaultsKey) as? [String: Bool] ?? [:]
        if let mode = saved[id] ?? (Self.englishFirst.contains(id) ? true : nil), engine.asciiMode != mode {
            engine.asciiMode = mode
        }
    }

    private func rememberAsciiMode(for client: Any?) {
        guard let id = bundleID(client) else { return }
        var saved = UserDefaults.standard.dictionary(forKey: Self.asciiDefaultsKey) as? [String: Bool] ?? [:]
        saved[id] = engine.asciiMode
        UserDefaults.standard.set(saved, forKey: Self.asciiDefaultsKey)
    }

    // MARK: - 联想 (prediction)

    private var predictions: [String]?

    /// While suggestions show: 1–6 or a click picks one (and suggests again),
    /// Esc hides them; any other key hides them and does its normal job.
    private func handlePredictionKey(_ event: NSEvent, client: IMKTextInput) -> Bool? {
        guard let list = predictions else { return nil }
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if plain, event.keyCode == UInt16(kVK_Escape) {
            dismissPredictions()
            return true
        }
        if plain, let c = event.characters, let n = Int(c), (1...list.count).contains(n) {
            commitPrediction(list[n - 1], client: client)
            return true
        }
        dismissPredictions()
        return nil
    }

    private func commitPrediction(_ text: String, client: IMKTextInput) {
        predictions = nil
        var state = EngineState()
        state.commitText = text
        state.asciiMode = false
        apply(state, to: client)          // inserts and may suggest again
    }

    /// 联想, the grid and the remembered menu belong to one composition;
    /// anything that ends it outside the normal key path drops all three.
    private func resetTransientUI() {
        predictions = nil
        grid = nil
        lastState = nil
    }

    private func dismissPredictions() {
        guard predictions != nil else { return }
        predictions = nil
        CandidatePanel.shared.hide()
    }

    private func pickCandidate(_ index: Int) {
        guard let client = currentClient as? IMKTextInput else { return }
        if let list = predictions, list.indices.contains(index) {
            commitPrediction(list[index], client: client)
            return
        }
        let state: EngineState?
        if let grid {
            state = engine.selectAbsolute(grid.start + index)
            self.grid = nil
        } else {
            state = engine.selectCandidate(at: index)
        }
        if let state { apply(state, to: client) }
    }

    // MARK: - Expanded candidate grid (Down arrow)

    private struct Grid {
        var start: Int
        var items: [Candidate]
        var highlight: Int
    }
    private var grid: Grid?
    private var lastState: EngineState?
    private static let gridColumns = 5
    private static let gridMax = 40

    /// Down opens the grid; inside it arrows move, Return/Space pick, Esc or
    /// Up from the first row closes it. Any other key closes it and types.
    private func handleGridKey(_ event: NSEvent, client: IMKTextInput) -> Bool? {
        let code = Int(event.keyCode)
        let plain = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        guard var g = grid else {
            guard plain, code == kVK_DownArrow, hasMarkedText,
                  let last = lastState, !last.candidates.isEmpty else { return nil }
            let start = last.pageNo * last.pageSize
            let items = engine.candidates(from: start, max: Self.gridMax)
            guard items.count > last.candidates.count else { return nil }   // nothing more to show
            grid = Grid(start: start, items: items, highlight: max(0, last.highlightedIndex))
            showGrid(client)
            return true
        }
        let cols = Self.gridColumns
        switch code {
        case kVK_RightArrow: g.highlight = min(g.items.count - 1, g.highlight + 1)
        case kVK_LeftArrow: g.highlight = max(0, g.highlight - 1)
        case kVK_DownArrow: g.highlight = min(g.items.count - 1, g.highlight + cols)
        case kVK_UpArrow:
            if g.highlight < cols { closeGrid(client); return true }
            g.highlight -= cols
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            pickCandidate(g.highlight)
            return true
        case kVK_Escape:
            closeGrid(client)
            return true
        default:
            grid = nil                     // keep typing; the row comes back
            return nil
        }
        grid = g
        showGrid(client)
        return true
    }

    private func showGrid(_ client: IMKTextInput) {
        guard let g = grid else { return }
        CandidatePanel.shared.showGrid(candidates: g.items, highlighted: g.highlight,
                                       caretRect: caretRect(in: client), columns: Self.gridColumns)
    }

    private func closeGrid(_ client: IMKTextInput) {
        grid = nil
        if let last = lastState { apply(last, to: client) }
    }

    // MARK: - Lifecycle

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        // The focused text field gets voice results.
        currentClient = sender as AnyObject
        VoiceSession.shared.target = self
        restoreAsciiMode(for: sender)
        // Mouse clicks in the candidate window pick for this client.
        CandidatePanel.shared.onSelect = { [weak self] index in self?.pickCandidate(index) }
    }

    override func deactivateServer(_ sender: Any!) {
        // Focus left the client: drop any half-typed code rather than leave
        // marked text behind.
        if let client = sender as? IMKTextInput { clearMarkedText(in: client) }
        engine.reset()
        resetTransientUI()
        currentClient = nil
        if VoiceSession.shared.target === self { VoiceSession.shared.target = nil }
        CandidatePanel.shared.hide()
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        // The client asked us to finish composing (e.g. mouse click
        // elsewhere): keep what was typed as plain letters, like other
        // Chinese input methods, instead of dropping it.
        let raw = engine.takeRawInput()
        if let client = sender as? IMKTextInput {
            clearMarkedText(in: client)
            if let raw { client.insertText(raw, replacementRange: Self.noReplacement) }
        }
        resetTransientUI()
        CandidatePanel.shared.hide()
    }

    // MARK: - Input menu
    //
    // Only three items; every other setting lives in ErgouIME Settings.

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let punct = menu.addItem(withTitle: "英文标点", action: #selector(toggleOption(_:)), keyEquivalent: "")
        punct.tag = 1
        punct.state = engine.option("ascii_punct") ? .on : .off
        punct.target = self
        let trad = menu.addItem(withTitle: "繁体输出", action: #selector(toggleOption(_:)), keyEquivalent: "")
        trad.tag = 2
        trad.state = engine.option("traditionalization") ? .on : .off
        trad.target = self
        let shape = menu.addItem(withTitle: "全角", action: #selector(toggleOption(_:)), keyEquivalent: "")
        shape.tag = 3
        shape.state = engine.option("full_shape") ? .on : .off
        shape.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "常用语…", action: #selector(showPhrases(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "语音记录…", action: #selector(showVoiceHistory(_:)), keyEquivalent: "").target = self
        addMicrophoneItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开设置…", action: #selector(openSettings(_:)), keyEquivalent: "").target = self
        let redeploy = menu.addItem(withTitle: "重新部署", action: #selector(redeploy(_:)), keyEquivalent: "")
        redeploy.target = self
        redeploy.isEnabled = EngineHost.shared.canRedeploy
        menu.addItem(withTitle: "关于二狗输入法", action: #selector(showAbout(_:)), keyEquivalent: "").target = self
        return menu
    }

    @objc private func toggleOption(_ sender: Any?) {
        // Tags, not representedObject: the item IMK hands back may be a copy.
        let names = [1: "ascii_punct", 2: "traditionalization", 3: "full_shape"]
        guard let tag = Self.menuItem(from: sender)?.tag, let name = names[tag] else { return }
        let on = !engine.option(name)
        engine.setOption(name, on)
        // Kept for every text field and across redeploys (MenuOptions).
        MenuOptions.save(name, on)
    }

    @objc private func showVoiceHistory(_ sender: Any?) {
        let style = Date.RelativeFormatStyle(presentation: .named)
        PickListWindow.voiceHistory.show(VoiceHistory.shared.recent.map {
            PickItem(id: $0.id.uuidString, text: $0.text, detail: $0.date.formatted(style))
        })
    }

    @objc private func showPhrases(_ sender: Any?) {
        PickListWindow.phrases.show(SharedSettings.quickPhrases.map {
            PickItem(id: $0.id, text: $0.text, detail: $0.code.isEmpty ? "" : "编码 \($0.code)")
        })
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsLauncher.open()
    }

    @objc private func redeploy(_ sender: Any?) {
        EngineHost.shared.redeploy()
    }

    @objc private func showAbout(_ sender: Any?) {
        SettingsLauncher.open(page: .about)
    }

    // MARK: - Applying engine state

    private func apply(_ state: EngineState, to client: IMKTextInput) {
        var timing = KeyTiming()
        apply(state, to: client, timing: &timing)
    }

    private func apply(_ state: EngineState, to client: IMKTextInput, timing: inout KeyTiming) {
        // Remembered for the grid; closing the grid replays it, so it must
        // not carry text that was already inserted.
        lastState = state
        lastState?.commitText = nil
        grid = nil
        timing.measure(\.client) {
            if let text = state.commitText, !text.isEmpty {
                client.insertText(spaced(text, in: client), replacementRange: Self.noReplacement)
                hasMarkedText = false
            }
            if state.preedit.isEmpty {
                clearMarkedText(in: client)
            } else {
                let marked = NSAttributedString(string: state.preedit, attributes: [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ])
                client.setMarkedText(marked,
                                     selectionRange: NSRange(location: state.preeditCursor, length: 0),
                                     replacementRange: Self.noReplacement)
                hasMarkedText = true
            }
        }

        // No 联想 with 繁体输出: the word list is simplified only.
        if let committed = state.commitText, state.preedit.isEmpty, state.candidates.isEmpty,
           !state.asciiMode, !SecureInput.isActive, !engine.option("traditionalization") {
            let next = Predictor.shared.suggestions(after: committed)
            if !next.isEmpty {
                predictions = next
                CandidatePanel.shared.show(candidates: next.enumerated().map {
                    Candidate(text: $0.element, comment: nil, label: "\($0.offset + 1)")
                }, highlighted: -1, caretRect: caretRect(in: client))
                return
            }
        }
        if state.candidates.isEmpty {
            timing.measure(\.panel) { CandidatePanel.shared.hide() }
        } else {
            let caret = timing.measure(\.caret) { caretRect(in: client) }
            timing.measure(\.panel) {
                CandidatePanel.shared.show(candidates: state.candidates,
                                           highlighted: state.highlightedIndex,
                                           caretRect: caret,
                                           hasPrevious: state.pageNo > 0,
                                           hasNext: !state.isLastPage)
            }
        }
    }

    /// `text` with a space in front when 中英文之间加空格 asks for one. Asks
    /// the app for the character before the caret (a synchronous call into
    /// the client) only when `text` starts with a Han character or a Latin
    /// letter or digit — not for punctuation.
    private func spaced(_ text: String, in client: IMKTextInput) -> String {
        guard SharedSettings.autoSpace, let first = text.first,
              AutoSpace.isHan(first) || AutoSpace.isLatin(first) else { return text }
        return AutoSpace.join(before: characterBeforeInsertion(client), text)
    }

    /// The character left of where text will go (before the marked text, if
    /// any). nil when the app does not tell us.
    private func characterBeforeInsertion(_ client: IMKTextInput) -> Character? {
        let marked = client.markedRange()
        let anchor = marked.location != NSNotFound && marked.length > 0 ? marked.location : client.selectedRange().location
        guard anchor != NSNotFound, anchor > 0,
              let s = client.attributedSubstring(from: NSRange(location: anchor - 1, length: 1))?.string
        else { return nil }
        return s.last
    }

    private func clearMarkedText(in client: IMKTextInput) {
        guard hasMarkedText else { return }
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                             replacementRange: Self.noReplacement)
        hasMarkedText = false
    }

    private func caretRect(in client: IMKTextInput) -> NSRect {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        return rect
    }
}

/// Where the time of one key goes. Durations only — never the key or any
/// text (Privacy rule 4). Logged at notice level so it is kept:
///   log show --last 10m --predicate 'subsystem == "com.codamon.inputmethod.Ergou" && category == "input"'
/// TODO(M5): drop to debug level once typing latency is settled.
struct KeyTiming {
    var engine: Double = 0   // librime
    var client: Double = 0   // insertText / setMarkedText (IPC to the app)
    var caret: Double = 0    // attributes(forCharacterIndex:) (IPC to the app)
    var panel: Double = 0    // candidate window layout + draw
    private let start = DispatchTime.now()

    @discardableResult
    mutating func measure<T>(_ part: WritableKeyPath<KeyTiming, Double>, _ body: () -> T) -> T {
        let t0 = DispatchTime.now()
        let result = body()
        self[keyPath: part] += Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
        return result
    }

    func log() {
        let total = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        Log.input.notice("key total=\(total, format: .fixed(precision: 2), privacy: .public) engine=\(engine, format: .fixed(precision: 2), privacy: .public) client=\(client, format: .fixed(precision: 2), privacy: .public) caret=\(caret, format: .fixed(precision: 2), privacy: .public) panel=\(panel, format: .fixed(precision: 2), privacy: .public)")
    }
}
