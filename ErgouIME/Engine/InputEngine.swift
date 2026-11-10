// ergou-ime — engine abstraction.
// SPDX-License-Identifier: GPL-3.0-only
//
// ErgouInputController talks only to `InputEngine`. Today there are two
// implementations:
//
//   PassthroughEngine — commits printable ASCII directly (always available)
//   RimeEngine        — librime + rime-wubi86-jidian (when ERGOU_WITH_RIME)
//
// The engine is pure text logic: it gets keys, returns what to commit and what
// to show. It never touches the network, the pasteboard or the disk outside
// Paths.appSupport.

import AppKit

/// A key event reduced to what engines need. Built from NSEvent in the controller.
struct KeyInput {
    enum Phase { case down, up }

    var keyCode: UInt16
    /// Characters ignoring modifiers except Shift (NSEvent.charactersIgnoringModifiers).
    var characters: String
    var modifiers: NSEvent.ModifierFlags
    var phase: Phase = .down
}

struct Candidate: Equatable {
    var text: String
    var comment: String?
    /// Label shown in front of the candidate, e.g. "1".
    var label: String?
}

/// What the engine wants the UI to show after a key.
struct EngineState: Equatable {
    /// Text to insert into the client now, if any.
    var commitText: String?
    /// Marked (inline, underlined) text; empty when not composing.
    var preedit: String = ""
    /// Caret position inside `preedit`, in UTF-16 units.
    var preeditCursor: Int = 0
    var candidates: [Candidate] = []
    var highlightedIndex: Int = 0
    var isLastPage: Bool = true
    /// 0-based page of the candidate menu.
    var pageNo: Int = 0
    /// Candidates per page (librime menu/page_size).
    var pageSize: Int = 5
    /// True when Chinese input is off and keys go through as Latin.
    var asciiMode: Bool = true
    /// False when the engine committed text but wants the client app to
    /// handle the key as well (e.g. Return after committing raw input).
    var consumedKey: Bool = true
}

protocol InputEngine: AnyObject {
    /// Feed one key. Returns nil if the engine did not consume it (the
    /// controller then lets the client app handle the key), otherwise the
    /// new state.
    func handle(_ key: KeyInput) -> EngineState?

    /// Pick candidate `index` on the current page (mouse click in the panel).
    func selectCandidate(at index: Int) -> EngineState?

    /// Drop any composition, e.g. when the client loses focus.
    func reset()

    /// The raw code being composed (e.g. "fjtk"), then clear the
    /// composition. For commitComposition: a mouse click elsewhere keeps
    /// what was typed, like other Chinese input methods.
    func takeRawInput() -> String?

    /// Up to `max` candidates starting at absolute index `index` (for the
    /// expanded candidate grid).
    func candidates(from index: Int, max: Int) -> [Candidate]

    /// Pick a candidate by absolute index (expanded grid).
    func selectAbsolute(_ index: Int) -> EngineState?

    /// Chinese ⇄ English toggle (Shift tap, M1).
    var asciiMode: Bool { get set }

    /// librime switches such as ascii_punct (英文标点) and full_shape (全角).
    func option(_ name: String) -> Bool
    func setOption(_ name: String, _ on: Bool)
}

/// Owns process-wide engine setup and hands out per-client engines.
final class EngineHost {
    static let shared = EngineHost()

    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        #if ERGOU_WITH_RIME
        RimeRuntime.shared.start()
        #else
        Log.engine.info("Built without librime; using passthrough engine")
        #endif

        // Requests from ErgouIME Settings.
        observers.append(SharedNotifications.observe(SharedNotifications.redeployRime) { [weak self] in
            self?.redeploy()
        })
        observers.append(SharedNotifications.observe(SharedNotifications.regeneratePhrases) {
            #if ERGOU_WITH_RIME
            RimeUserConfig.writePhrases(Paths.rimeUserData)
            #endif
        })
        // 我的词: applies Settings' edits to the learned terms, keeps the hotwords.
        TermStore.shared.start()
        observers.append(SharedNotifications.observe(SharedNotifications.clearVoiceHistory) {
            VoiceHistory.shared.clear()
        })
        observers.append(SharedNotifications.observe(SharedNotifications.clearUserDictionary) {
            #if ERGOU_WITH_RIME
            RimeRuntime.shared.clearUserDictionary()
            #endif
        })
    }

    func redeploy() {
        #if ERGOU_WITH_RIME
        RimeRuntime.shared.redeploy()
        #endif
    }

    var canRedeploy: Bool {
        #if ERGOU_WITH_RIME
        return true
        #else
        return false
        #endif
    }

    /// One engine per IMKInputController (i.e. per client text field).
    func makeEngine() -> InputEngine {
        #if ERGOU_WITH_RIME
        if let rime = RimeEngine() {
            return rime
        }
        Log.engine.error("librime session unavailable; falling back to passthrough")
        #endif
        return PassthroughEngine()
    }
}

/// The input menu's switches (英文标点, 繁体输出, 全角). librime keeps options
/// per session, i.e. per text field, and only saves them when changed through
/// its own switcher; the menu goes through set_option. So they are kept here,
/// in the input method's own defaults, and applied to every session after it
/// selects its schema (RimeEngine.ensureSession).
enum MenuOptions {
    static let names: Set<String> = ["ascii_punct", "traditionalization", "full_shape"]
    private static let defaultsKey = "menuOptions"

    /// Bumped on every change, so open sessions pick it up on their next key.
    private(set) static var version = 0

    static var saved: [String: Bool] {
        let all = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool] ?? [:]
        return all.filter { names.contains($0.key) }
    }

    static func save(_ name: String, _ on: Bool) {
        guard names.contains(name) else { return }
        var all = saved
        all[name] = on
        UserDefaults.standard.set(all, forKey: defaultsKey)
        version += 1
    }
}
