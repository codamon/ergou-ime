// ergou-ime — the voice key from any input source (M3 T3.2). Right Option
// unless the user recorded another key in Settings (Shared/KeyOptions.swift).
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
            // Only when Settings asked just now (SharedRequest), not for any
            // process that posts the notification.
            if SharedRequest.requestInputMonitoring.consume() { self?.requestPermission() }
        })
        // Settings is recording a shortcut: those keys are not for us.
        // Believed only with Settings' mark in the shared settings (anyone
        // can post the notification, ShortcutRecordingMark). This process
        // may see the new value a moment after the notification: look again.
        observers.append(SharedNotifications.observe(SharedNotifications.shortcutRecordingBegan) { [weak self] in
            func stand() -> Bool {
                guard ShortcutRecordingMark.isFresh else { return false }
                VoiceSession.shared.shortcutRecording(true)
                self?.recorderBusy(true)
                return true
            }
            if !stand() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { _ = stand() } }
        })
        observers.append(SharedNotifications.observe(SharedNotifications.shortcutRecordingEnded) { [weak self] in
            VoiceSession.shared.shortcutRecording(false)
            self?.recorderBusy(false)
        })
        observers.append(SharedNotifications.observe(SharedNotifications.globalVoiceChanged) { [weak self] in
            self?.applySetting()
        })
        // Mouse buttons, in any app: a modifier held for a click was not
        // tapped. Mouse events need no permission to watch; nothing about
        // them is kept but the time.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            VoiceSession.shared.interrupted()
        }
        applySetting()
    }

    private var mouseMonitor: Any?

    private func applySetting() {
        if SharedSettings.globalVoice {
            if !isRunning { install() }
        } else {
            uninstall()
        }
        applyHotKey()
        publishStatus()
    }

    /// Voice can be started under another input source: by the tap, or by
    /// the system-wide hot key.
    var isGlobal: Bool { isRunning || hotKeyRegistered }

    /// True at most once a day, while 在其他输入法下也能用 is on, the voice
    /// key is a single modifier key (which needs the tap) and Input
    /// Monitoring is not allowed.
    func shouldRemindPermission() -> Bool {
        guard SharedSettings.globalVoice, Shortcuts.current.voice.isTap, !isRunning,
              !CGPreflightListenEventAccess() else { return false }
        let key = "inputMonitoringRemindedAt"
        if let last = UserDefaults.standard.object(forKey: key) as? Date, abs(last.timeIntervalSinceNow) < 24 * 3600 {
            return false
        }
        UserDefaults.standard.set(Date(), forKey: key)
        return true
    }

    // MARK: - A recorded key with modifiers (⌃Space …)
    //
    // The tap only listens, so it could not keep such a key from also
    // reaching the app. A Carbon hot key is taken by the system before any
    // app or input method sees it, and needs no permission.

    /// True while the voice shortcut is registered system-wide.
    private(set) var hotKeyRegistered = false
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var registeredShortcut: Shortcut?
    /// The last registration was refused (another app has the key).
    private var hotKeyFailed = false

    /// While Settings records a shortcut the hot key is given up: the
    /// system takes a registered key before any app sees it, so pressing
    /// the current shortcut in the recorder recorded only its modifier
    /// (⌥菜单键 came out as 右 Option and could not be chosen again, D
    /// 2026-11-12). Until when (system uptime); see shortcutRecordingHold.
    private var recorderBusyUntil: TimeInterval = 0
    private var resumeHotKey: DispatchWorkItem?

    private func recorderBusy(_ busy: Bool) {
        resumeHotKey?.cancel()
        resumeHotKey = nil
        if busy {
            let hold = SharedNotifications.shortcutRecordingHold
            recorderBusyUntil = ProcessInfo.processInfo.systemUptime + hold
            // Settings may never say it finished (it quit): take the key back.
            let work = DispatchWorkItem { [weak self] in self?.applyHotKey() }
            resumeHotKey = work
            DispatchQueue.main.asyncAfter(deadline: .now() + hold + 0.1, execute: work)
        } else {
            recorderBusyUntil = 0
        }
        applyHotKey()
        publishStatus()               // the key may just have been (re)registered, or refused
    }

    private func applyHotKey() {
        let voice = Shortcuts.read().voice
        let free = ProcessInfo.processInfo.systemUptime >= recorderBusyUntil
        let wanted: Shortcut? = SharedSettings.globalVoice && !voice.isTap && free ? voice : nil
        if wanted == registeredShortcut { return }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        hotKeyRegistered = false
        hotKeyFailed = false
        registeredShortcut = wanted
        guard let wanted else { return }
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { VoiceSession.shared.shortcutPressed() }
                return noErr
            }, 1, &spec, nil, &hotKeyHandler)
        }
        var carbon: UInt32 = 0
        if wanted.modifiers & Shortcut.command != 0 { carbon |= UInt32(cmdKey) }
        if wanted.modifiers & Shortcut.shift != 0 { carbon |= UInt32(shiftKey) }
        if wanted.modifiers & Shortcut.option != 0 { carbon |= UInt32(optionKey) }
        if wanted.modifiers & Shortcut.control != 0 { carbon |= UInt32(controlKey) }
        let id = EventHotKeyID(signature: OSType(0x4552_474F), id: 1)       // 'ERGO'
        let status = RegisterEventHotKey(UInt32(wanted.keyCode), carbon, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        hotKeyRegistered = status == noErr && hotKeyRef != nil
        if !hotKeyRegistered {
            // Not remembered as registered, so the next applySetting (a
            // setting changes, Settings asks) tries again: the app that
            // had the key may be gone by then (audit 0.7.0 L2).
            registeredShortcut = nil
            hotKeyFailed = true
            // Taken by another app, or refused: the controller still
            // handles the key while 二狗 is the input source.
            Log.speech.error("global voice key: could not register the hot key (\(status, privacy: .public))")
        }
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
        else if !Shortcuts.read().voice.isTap {
            // Given up for a moment while Settings records a shortcut: still "on".
            status = hotKeyFailed ? "failed" : "on"
        }
        else if isRunning { status = "on" }
        else if !CGPreflightListenEventAccess() { status = "needsPermission" }
        else { status = "failed" }
        Paths.sharedDefaults.set(status, forKey: SettingKey.globalVoiceStatus)
    }

    // MARK: - Events

    /// Every modifier key: ⌘ ⇧ ⇪ ⌥ ⌃ fn, left and right.
    private static let modifiers: Set<Int64> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            // Right Option unless changed in Settings. Events from the tap
            // carry the device bits, so this tells the key from its twin on
            // the other side (Right Option: NX_DEVICERALTKEYMASK); "cannot
            // tell" counts as up.
            let voiceKey = Shortcuts.current.voice
            if voiceKey.isTap, code == Int64(voiceKey.keyCode) {
                let down = voiceKey.isDown(flags: UInt(event.flags.rawValue)) ?? false
                DispatchQueue.main.async {
                    if down { VoiceSession.shared.voiceKeyDown() } else { VoiceSession.shared.voiceKeyUp() }
                }
            } else if Self.modifiers.contains(code) {
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
