// ergou-ime — Right Option from any input source (M3 T3.2).
// SPDX-License-Identifier: GPL-3.0-only
//
// A listen-only CGEventTap in the input method process. It only watches
// flagsChanged and keyDown, never changes or swallows an event (Fn, Option
// and everything else reach the system and the app unchanged), and needs
// the Input Monitoring permission only — not Accessibility.
//
// While the tap runs it is the single Right Option detector; the
// controller's flagsChanged path stands down (`isRunning`) so one press is
// never handled twice. Esc / Return during voice are taken from here only
// when another input source is active (our controller handles them
// otherwise). The key events themselves are not recorded or logged: only
// key codes for Right Option, Esc and Return are looked at.

import AppKit
import Carbon

final class GlobalHotkey {
    static let shared = GlobalHotkey()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var permissionPoll: Timer?

    /// True while the tap is installed and enabled.
    private(set) var isRunning = false

    private init() {}

    /// Called once at launch.
    func start() {
        observers.append(SharedNotifications.observe(SharedNotifications.requestInputMonitoring) { [weak self] in
            self?.requestPermission()
        })
        observers.append(SharedNotifications.observe(SharedNotifications.globalVoiceChanged) { [weak self] in
            self?.applySetting()
        })
        applySetting()
    }

    private func applySetting() {
        if SharedSettings.globalVoice {
            if !isRunning { install() }
        } else {
            uninstall()
        }
        publishStatus()
    }

    /// Settings › 语音 asked: show the system prompt (or open the pane),
    /// then keep checking for a minute so the tap starts once allowed.
    private func requestPermission() {
        guard !CGPreflightListenEventAccess() else { applySetting(); return }
        _ = CGRequestListenEventAccess()
        permissionPoll?.invalidate()
        var tries = 0
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            tries += 1
            if CGPreflightListenEventAccess() || tries > 120 {
                timer.invalidate()
                self?.applySetting()
            }
        }
    }

    private func install() {
        guard CGPreflightListenEventAccess() else {
            Log.speech.notice("global voice key: Input Monitoring not allowed yet")
            return
        }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                          options: .listenOnly, eventsOfInterest: CGEventMask(mask),
                                          callback: { _, type, event, info in
                                              if let info {
                                                  Unmanaged<GlobalHotkey>.fromOpaque(info).takeUnretainedValue()
                                                      .handle(type, event)
                                              }
                                              return Unmanaged.passUnretained(event)
                                          },
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            Log.speech.error("global voice key: could not create the event tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isRunning = true
        Log.speech.notice("global voice key: listening")
    }

    private func uninstall() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        isRunning = false
    }

    private func publishStatus() {
        let status: String
        if !SharedSettings.globalVoice { status = "off" }
        else if isRunning { status = "on" }
        else if !CGPreflightListenEventAccess() { status = "needsPermission" }
        else { status = "failed" }
        Paths.sharedDefaults.set(status, forKey: SettingKey.globalVoiceStatus)
    }

    // MARK: - Events

    private static let rightOption: Int64 = 61
    private static let otherModifiers: Set<Int64> = [54, 55, 56, 57, 58, 59, 60, 62, 63]   // ⌘ ⇧ ⇪ ⌥ ⌃ fn

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if code == Self.rightOption {
                // NX_DEVICERALTKEYMASK: Right Option itself, not Left.
                let down = event.flags.rawValue & 0x40 != 0
                DispatchQueue.main.async {
                    if down { VoiceSession.shared.rightOptionDown() } else { VoiceSession.shared.rightOptionUp() }
                }
            } else if Self.otherModifiers.contains(code) {
                DispatchQueue.main.async { VoiceSession.shared.keyPressed() }
            }
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            DispatchQueue.main.async {
                let session = VoiceSession.shared
                session.keyPressed()
                // Our controller handles these when it is the active one.
                guard session.isActive, session.target == nil else { return }
                if code == Int64(kVK_Escape) { session.cancel() }
                else if code == Int64(kVK_Return), session.isTidying { session.skipTidy() }
            }
        default:
            break
        }
    }
}
