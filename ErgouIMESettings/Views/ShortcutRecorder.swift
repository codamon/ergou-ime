// ErgouIME Settings — a field that records a shortcut.
// SPDX-License-Identifier: GPL-3.0-only
//
// Click it, press the key you want — one modifier key on its own (Right
// Option, Left Shift, Fn …) or a key with ⌃ ⌥ ⌘ (⌃Space, F5) — then Return,
// or click anywhere else, to keep it. Esc leaves it as it was; Delete goes
// back to the default. The keys pressed here are looked at only to build
// the shortcut; nothing else is stored (Shared/KeyOptions.swift, Shortcut).

import AppKit
import SwiftUI

/// One row's recorder with its "恢复默认" button and error line.
struct ShortcutRecorderRow: View {
    /// nil: the default is in use.
    let current: Shortcut?
    let defaultTitle: String
    /// A reason not to accept the shortcut, or nil.
    let reject: (Shortcut) -> String?
    /// nil: back to the default.
    let save: (Shortcut?) -> Void

    @State private var error: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 8) {
                // Always there, greyed out for the default, so the field
                // does not move when a shortcut is recorded.
                Button("恢复默认") { error = nil; save(nil) }
                    .buttonStyle(.link)
                    .disabled(current == nil)
                ShortcutRecorder(title: current?.title ?? defaultTitle) { recorded in
                    guard let recorded else { error = nil; save(nil); return }
                    if let reason = reject(recorded) { error = reason; return }
                    error = nil
                    save(recorded)
                }
                .frame(width: 150, height: 24)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let title: String
    /// The shortcut the user kept; nil: Delete (back to the default).
    let commit: (Shortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView { ShortcutRecorderView() }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.title = title
        view.commit = commit
    }
}

final class ShortcutRecorderView: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var commit: ((Shortcut?) -> Void)?

    private var recording = false { didSet { needsDisplay = true } }
    private var pending: Shortcut? { didSet { needsDisplay = true } }
    /// The one modifier key that went down since everything was up, if no
    /// other key joined it: released like that, it is a tap.
    private var loneModifier: UInt16?
    private var hint: String? { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.button)
        setAccessibilityLabel("录制快捷键")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // The first click counts even when the window was not the active one.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Every click starts recording (again). It never ends it: a second
    /// click used to stop the recording the first one had started, so a
    /// double click, or a click to "try again", did nothing (D, 2026-11-12).
    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    /// Recording does not depend on becoming first responder: AppKit does
    /// not call becomeFirstResponder for a view that already is, and then a
    /// click did nothing.
    private func beginRecording() {
        pending = nil
        loneModifier = nil
        hint = nil
        recording = true
        // The input method leaves the voice key alone meanwhile; said again
        // every few seconds, because it only believes it for a short time.
        SharedNotifications.post(SharedNotifications.shortcutRecordingBegan)
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: SharedNotifications.shortcutRecordingHold / 2, repeats: true) { _ in
            SharedNotifications.post(SharedNotifications.shortcutRecordingBegan)
        }
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
    }

    private var holdTimer: Timer?

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    /// Losing the focus keeps what was pressed, like Return.
    override func resignFirstResponder() -> Bool {
        finish(keep: true, resign: false)
        needsDisplay = true
        return true
    }

    private var keyObserver: NSObjectProtocol?

    /// Another window or app comes to the front: the same as losing the focus.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        guard let window else { return }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                                             queue: .main) { [weak self] _ in
            self?.finish(keep: true)
        }
    }

    deinit {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        holdTimer?.invalidate()
    }

    /// Ends recording; `keep`: save what was pressed, if anything.
    private func finish(keep: Bool, resign: Bool = true) {
        guard recording else { return }
        holdTimer?.invalidate()
        holdTimer = nil
        // A moment later: the key that ended it (or was just released) must
        // not count as the voice key either.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if self?.recording != true { SharedNotifications.post(SharedNotifications.shortcutRecordingEnded) }
        }
        let kept = keep ? pending : nil
        recording = false
        pending = nil
        loneModifier = nil
        if resign, window?.firstResponder === self { window?.makeFirstResponder(nil) }
        if let kept { commit?(kept) }
    }

    // ⌘-combinations arrive here, not in keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            // Reached with Tab: Space or Return starts recording, as a click does.
            if [49, 36, 76].contains(Int(event.keyCode)) { beginRecording() } else { super.keyDown(with: event) }
            return
        }
        loneModifier = nil
        let modifiers = event.modifierFlags.rawValue & Shortcut.modifierMask
        if modifiers == 0 {
            switch Int(event.keyCode) {
            case 36, 76: finish(keep: true); return                     // Return, keypad Enter
            case 53: finish(keep: false); return                        // Esc
            case 51, 117:                                               // Delete: the default
                finish(keep: false)
                commit?(nil)
                return
            default: break
            }
        }
        let shortcut = Shortcut(keyCode: event.keyCode, modifiers: modifiers, isTap: false, label: Self.label(for: event))
        if shortcut.isValid {
            pending = shortcut
            hint = nil
        } else {
            hint = "要带 ⌃ ⌥ ⌘"
            NSSound.beep()
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else { super.flagsChanged(with: event); return }
        let held = event.modifierFlags.rawValue & (Shortcut.modifierMask | 0x800000)       // + Fn
        if held == 0 {
            // Everything is up again: one modifier pressed alone was a tap.
            if let key = loneModifier {
                pending = .tap(key)
                hint = nil
            }
            loneModifier = nil
        } else if Shortcut.modifierKeys[event.keyCode] != nil, Shortcut.tap(event.keyCode).isDown(flags: event.modifierFlags.rawValue) != false {
            // First modifier down: a candidate. A second one: a combination.
            loneModifier = loneModifier == nil && held.nonzeroBitCount == 1 ? event.keyCode : nil
        }
    }

    private static let keyNames: [UInt16: String] = [
        110: "菜单键", 114: "Help", 71: "Clear",
        49: "Space", 36: "↩", 76: "⌤", 48: "⇥", 51: "⌫", 117: "⌦", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    private static func label(for event: NSEvent) -> String {
        if let name = keyNames[event.keyCode] { return name }
        let s = (event.charactersIgnoringModifiers ?? "").uppercased()
        if let first = s.first, !first.isWhitespace, first.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value != 0x7F && $0.value < 0xF700 }) {
            return String(first)
        }
        return "键 \(event.keyCode)"
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlColor).setFill()
        box.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        box.lineWidth = 1
        box.stroke()
        let text: String
        var colour = NSColor.labelColor
        if !recording {
            text = title
        } else if let pending {
            text = pending.title + "  ↩"
        } else {
            text = hint ?? "按下按键…"
            colour = .secondaryLabelColor
        }
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: recording ? .regular : .medium), .foregroundColor: colour,
        ])
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded()))
    }
}

/// Asking for the Input Monitoring permission (语音键 as a single modifier
/// key under other input sources).
enum InputMonitoringPrompt {
    /// The input method asks the system (it is the program that needs the
    /// permission), which shows its dialog only the first time ever; after
    /// that the request does nothing visible and "允许…" seemed dead (D,
    /// 2026-11-12). So the pane where the switch is gets opened as well.
    static func ask() {
        SharedRequest.requestInputMonitoring.post()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
