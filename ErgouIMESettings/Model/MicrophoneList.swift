// ErgouIME Settings — live list of microphones for the 语音 page.
// SPDX-License-Identifier: GPL-3.0-only

import CoreAudio
import Foundation

final class MicrophoneList: ObservableObject {
    @Published private(set) var inputs: [AudioInput] = AudioInputs.all()
    private var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
    private var defaultAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                            mScope: kAudioObjectPropertyScopeGlobal,
                                                            mElement: kAudioObjectPropertyElementMain)
    private let listener: AudioObjectPropertyListenerBlock

    init() {
        weak var weakSelf: MicrophoneList?
        listener = { _, _ in
            DispatchQueue.main.async { weakSelf?.inputs = AudioInputs.all() }
        }
        weakSelf = self
        let system = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main, listener)
        AudioObjectAddPropertyListenerBlock(system, &defaultAddress, DispatchQueue.main, listener)
    }

    deinit {
        let system = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectRemovePropertyListenerBlock(system, &address, DispatchQueue.main, listener)
        AudioObjectRemovePropertyListenerBlock(system, &defaultAddress, DispatchQueue.main, listener)
    }
}
