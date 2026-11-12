// ergou-ime — watches which input source is selected (InputSourceSwitch).
// SPDX-License-Identifier: GPL-3.0-only

import Carbon
import Foundation

final class InputSourceWatcher {
    static let shared = InputSourceWatcher()

    /// The user switched to 二狗 from another input source. Main thread.
    var onSwitchedIn: (() -> Void)?

    private var state = InputSourceSwitch(oursSelected: InputSourceWatcher.oursIsSelected())
    private var ignoreUntil: TimeInterval = 0

    private init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { [weak self] _ in self?.changed() }
    }

    /// Start watching. Safe to call again.
    func start() {}

    /// The input method is about to switch sources itself (ForeignInsert
    /// types a voice result through 二狗 and switches back).
    func ignoreChanges(for seconds: TimeInterval) {
        ignoreUntil = ProcessInfo.processInfo.systemUptime + seconds
    }

    private func changed() {
        let ours = Self.oursIsSelected()
        let wanted = state.changed(toOurs: ours, secureInput: SecureInput.isActive)
        guard wanted, ProcessInfo.processInfo.systemUptime >= ignoreUntil else { return }
        Log.input.notice("input source switched to ours: starting in Chinese")
        onSwitchedIn?()
    }

    private static func oursIsSelected() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
        let id = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        return InputSourceRegistrar.inputModeIDs.contains(id)
            || id.hasPrefix(Bundle.main.bundleIdentifier ?? "com.codamon.inputmethod.Ergou")
    }
}
