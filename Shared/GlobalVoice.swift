// ergou-ime — settings for the voice key under other input sources (M3).
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

extension SettingKey {
    /// Bool, Right Option works under any input source (needs Input Monitoring). Default true.
    static let globalVoice = "globalVoice"
    /// String written by the input method: on / off / needsPermission / failed.
    static let globalVoiceStatus = "globalVoiceStatus"
}

extension SharedSettings {
    static var globalVoice: Bool {
        Paths.sharedDefaults.object(forKey: SettingKey.globalVoice) as? Bool ?? true
    }
}

extension SharedNotifications {
    /// Settings → input method: ask for Input Monitoring.
    static let requestInputMonitoring = "com.codamon.ergou.request-input-monitoring"
    /// Settings → input method: the 其他输入法下 toggle changed.
    static let globalVoiceChanged = "com.codamon.ergou.global-voice-changed"
}
