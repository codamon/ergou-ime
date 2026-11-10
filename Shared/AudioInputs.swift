// ergou-ime — which microphone voice input records from.
// SPDX-License-Identifier: GPL-3.0-only
//
// The user can pick a microphone (Settings › 语音, or the input menu). The
// choice is remembered by Core Audio UID, so it is used again whenever that
// device is connected and skipped (automatic choice) while it is not.
//
// Automatic: the system default input, except
//   - a Bluetooth headset is the default and the lid is open → the built-in
//     mic (headsets drop to a narrow-band call profile; preferBuiltInMic);
//   - the default is the built-in mic but the lid is closed → another input.
// With the lid closed the built-in mic is still listed but records silence
// (D's MacBook Pro with an external display, 2026-11-09).
//
// The stored UID is untrusted input (it comes from the shared defaults): it
// is only compared against the UIDs Core Audio reports.

import CoreAudio
import Foundation
import IOKit

struct AudioInput: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32

    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}

enum AudioInputs {
    /// Devices with at least one input stream, in Core Audio order.
    static func all() -> [AudioInput] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasInput(id), let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = string(id, kAudioObjectPropertyName) ?? uid
            return AudioInput(id: id, uid: uid, name: name, transport: uint32(id, kAudioDevicePropertyTransportType) ?? 0)
        }
    }

    static var defaultInputID: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    /// True when a MacBook's lid is closed (IOPMrootDomain AppleClamshellState).
    /// False when unknown or on Macs without a lid.
    static var lidClosed: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                                                    kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (value as? Bool) ?? false
    }

    /// The device to record from; nil = leave the system default alone.
    /// `chosenUID` empty = automatic.
    static func resolve(chosenUID: String, preferBuiltInOverBluetooth: Bool) -> AudioInput? {
        let inputs = all()
        if !chosenUID.isEmpty, let chosen = inputs.first(where: { $0.uid == chosenUID }) {
            return chosen
        }
        let closed = lidClosed
        let current = defaultInputID.flatMap { id in inputs.first { $0.id == id } }
        if let current, current.isBuiltIn, closed {
            // Prefer a wired/USB mic, then anything that is not built in.
            return inputs.first { !$0.isBuiltIn && $0.transport == kAudioDeviceTransportTypeUSB }
                ?? inputs.first { !$0.isBuiltIn }
        }
        if let current, current.isBluetooth, preferBuiltInOverBluetooth, !closed,
           let builtIn = inputs.first(where: \.isBuiltIn) {
            return builtIn
        }
        return nil
    }

    /// The name of the device `resolve` would use, for the HUD and Settings.
    static func effectiveName(chosenUID: String, preferBuiltInOverBluetooth: Bool) -> String? {
        if let device = resolve(chosenUID: chosenUID, preferBuiltInOverBluetooth: preferBuiltInOverBluetooth) {
            return device.name
        }
        guard let id = defaultInputID else { return nil }
        return string(id, kAudioObjectPropertyName)
    }

    // MARK: - Core Audio helpers

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}

extension SettingKey {
    /// String, Core Audio UID of the chosen microphone; "" or missing = automatic.
    static let microphoneUID = "microphoneUID"
    /// String, that microphone's name, shown while it is not connected.
    static let microphoneName = "microphoneName"
}

extension SharedSettings {
    /// At most 512 characters; anything longer is treated as automatic.
    static var microphoneUID: String {
        let raw = Paths.sharedDefaults.string(forKey: SettingKey.microphoneUID) ?? ""
        return raw.count <= 512 ? raw : ""
    }

    static func chooseMicrophone(_ input: AudioInput?) {
        Paths.sharedDefaults.set(input?.uid ?? "", forKey: SettingKey.microphoneUID)
        Paths.sharedDefaults.set(input?.name ?? "", forKey: SettingKey.microphoneName)
    }
}
