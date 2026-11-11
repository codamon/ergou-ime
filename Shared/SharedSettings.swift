// ergou-ime — settings keys and cross-process notifications.
// SPDX-License-Identifier: GPL-3.0-only
//
// Settings writes, the input method reads (Paths.sharedDefaults). Requests
// that need the input method to act (redeploy, clear userdb) go through
// Darwin notifications, which carry no payload and work across sandboxes.

import Foundation

enum SpeechEngineKind: String, CaseIterable {
    /// SenseVoice Small int8 via sherpa-onnx (first implementation, M2).
    case senseVoice
    /// Whisper (MIT weights) via sherpa-onnx — second implementation, before M6.
    case whisper
}

/// How recognised speech is cleaned up after punctuation (D, 2026-11-09):
/// fix homophone errors, keep only what the speaker settled on ("A，不对，
/// 应该是 B" → B), drop fillers. Chosen in ErgouIME Settings.
enum VoiceCorrection: String, CaseIterable, Identifiable {
    /// Apple Intelligence on-device model (Foundation Models). Free, offline.
    case apple
    /// A small open model downloaded once, run on this Mac. Offline.
    case local
    /// A cloud model. Opt-in; the text leaves the Mac. Runs in the
    /// ErgouIME Cloud XPC service, never in the input method (which has no
    /// network access). Shared/CloudTidy.swift.
    case cloud
    /// Punctuation only.
    case off

    var id: String { rawValue }
}

/// Which Rime schema the input method uses (D, 2026-11-09). Pinyin is the
/// default since 2026-11-10 (D: 五笔 is a niche need); installs that already
/// ran with the old default keep 五笔 (migrateDefaultScheme).
enum InputScheme: String, CaseIterable, Identifiable {
    /// ergou_pinyin_ime: plain pinyin input method. Default.
    case pinyin
    /// ergou_wubi: Wubi 86 with pinyin mixed in, Wubi first.
    case wubiMixed = "wubi"

    static let `default`: InputScheme = .pinyin

    var id: String { rawValue }
    var schemaID: String { self == .wubiMixed ? "ergou_wubi" : "ergou_pinyin_ime" }
}

enum SettingKey {
    /// Bool, 自动调频 (librime enable_user_dict), default
    /// PrivacyPolicy.frequencyLearningDefault.
    static let frequencyLearning = "frequencyLearning"
    /// String raw value of SpeechEngineKind, default .senseVoice.
    static let speechEngine = "speechEngine"
    /// Bool, 自动检查更新 (once a day), default
    /// PrivacyPolicy.automaticUpdateChecksDefault (true).
    static let automaticUpdateChecks = "automaticUpdateChecks"
    /// Date of the last update check that reached GitHub (written by Settings).
    static let lastUpdateCheck = "lastUpdateCheck"
    /// String, version the user chose to skip ("跳过这个版本").
    static let skippedUpdateVersion = "skippedUpdateVersion"
    /// Bool, the 新手引导 has been shown (written by Settings when it shows it).
    static let welcomeShown = "welcomeShown"

    // ---- mixed wubi + pinyin input (M1.5, discussion §3.5) ----
    /// Bool, 四码唯一自动上屏, default false. On also demotes pinyin below wubi.
    static let autoCommitUnique = "autoCommitUnique"
    /// Bool, default false. true = commit a unique 4-key code even if it
    /// could still be pinyin (long pinyin then needs the ` prefix).
    static let autoCommitStrict = "autoCommitStrict"
    /// [String], ids of FuzzyPinyin that are on.
    static let fuzzyPinyin = "fuzzyPinyin"
    /// Bool, 拼音容错 (adjacent keys + common swaps), default true.
    static let pinyinCorrection = "pinyinCorrection"
    /// Bool, 五笔容错 on empty codes, default true.
    static let wubiCorrection = "wubiCorrection"
    /// String raw value of InputScheme, default InputScheme.default (.pinyin).
    static let inputScheme = "inputScheme"
    /// Bool, keep a local history of voice results (input method's own
    /// container only), default true.
    static let voiceHistoryEnabled = "voiceHistoryEnabled"
    /// Bool, insert a space between Chinese and Latin letters/digits, default true.
    static let autoSpace = "autoSpace"
    /// String raw value of VoiceCorrection, default .apple.
    static let voiceCorrection = "voiceCorrection"
    /// Bool, record from the Mac's built-in microphone even when a headset
    /// is the default input (Bluetooth headsets drop to a narrow-band call
    /// profile and recognition gets worse). Default true.
    static let preferBuiltInMic = "preferBuiltInMic"
    /// [String], manual phrases, each "<text>\t<code>" (手动造词, M3 T3.8).
    static let manualPhrases = "manualPhrases"
}

/// Fuzzy pinyin pairs. Raw values are shared with
/// RimeData/lua/ergou/pinyin.lua (M.FUZZY) and ergou_pinyin's algebra.
enum FuzzyPinyin: String, CaseIterable, Identifiable {
    case zh_z, ch_c, sh_s, n_l, en_eng, in_ing, an_ang, f_h, r_l

    var id: String { rawValue }

    static let defaults: [FuzzyPinyin] = [.zh_z, .ch_c, .sh_s, .n_l, .en_eng, .in_ing]

    var label: String {
        switch self {
        case .zh_z: return "z = zh"
        case .ch_c: return "c = ch"
        case .sh_s: return "s = sh"
        case .n_l: return "n = l"
        case .en_eng: return "en = eng"
        case .in_ing: return "in = ing"
        case .an_ang: return "an = ang"
        case .f_h: return "f = h"
        case .r_l: return "r = l"
        }
    }

    /// Rime speller/algebra derive rules for this pair.
    var algebra: [String] {
        switch self {
        case .zh_z: return ["derive/^zh/z/", "derive/^z([^h])/zh$1/"]
        case .ch_c: return ["derive/^ch/c/", "derive/^c([^h])/ch$1/"]
        case .sh_s: return ["derive/^sh/s/", "derive/^s([^h])/sh$1/"]
        case .n_l: return ["derive/^n/l/", "derive/^l/n/"]
        case .en_eng: return ["derive/en$/eng/", "derive/eng$/en/"]
        case .in_ing: return ["derive/in$/ing/", "derive/ing$/in/"]
        case .an_ang: return ["derive/an$/ang/", "derive/ang$/an/"]
        case .f_h: return ["derive/^f/h/", "derive/^h/f/"]
        case .r_l: return ["derive/^r/l/", "derive/^l/r/"]
        }
    }
}

enum SharedSettings {
    static var speechEngine: SpeechEngineKind {
        let raw = Paths.sharedDefaults.string(forKey: SettingKey.speechEngine) ?? ""
        return SpeechEngineKind(rawValue: raw) ?? .senseVoice
    }

    static var automaticUpdateChecks: Bool {
        bool(SettingKey.automaticUpdateChecks, default: PrivacyPolicy.automaticUpdateChecksDefault)
    }

    /// Only a real Date counts.
    static var lastUpdateCheck: Date? {
        Paths.sharedDefaults.object(forKey: SettingKey.lastUpdateCheck) as? Date
    }

    static var frequencyLearning: Bool {
        bool(SettingKey.frequencyLearning, default: PrivacyPolicy.frequencyLearningDefault)
    }

    static var inputScheme: InputScheme {
        InputScheme(rawValue: Paths.sharedDefaults.string(forKey: SettingKey.inputScheme) ?? "") ?? .default
    }

    /// Before 2026-11-10 the default was 五笔拼音混输 and only a changed
    /// choice was stored. An install that has used Rime before (its user
    /// directory has installation.yaml) and never stored a choice was on
    /// 五笔: store that, so the new default does not switch it to pinyin.
    /// Input method only, before librime is set up.
    static func migrateDefaultScheme(rimeUserData: URL) {
        let defaults = Paths.sharedDefaults
        guard defaults.object(forKey: SettingKey.inputScheme) == nil,
              FileManager.default.fileExists(atPath: rimeUserData.appendingPathComponent("installation.yaml").path)
        else { return }
        defaults.set(InputScheme.wubiMixed.rawValue, forKey: SettingKey.inputScheme)
    }
    static var voiceHistoryEnabled: Bool { bool(SettingKey.voiceHistoryEnabled, default: true) }
    static var autoSpace: Bool { bool(SettingKey.autoSpace, default: true) }

    static var voiceCorrection: VoiceCorrection {
        VoiceCorrection(rawValue: Paths.sharedDefaults.string(forKey: SettingKey.voiceCorrection) ?? "") ?? .apple
    }
    static var preferBuiltInMic: Bool { bool(SettingKey.preferBuiltInMic, default: true) }
    static var autoCommitUnique: Bool { bool(SettingKey.autoCommitUnique, default: false) }
    static var autoCommitStrict: Bool { bool(SettingKey.autoCommitStrict, default: false) }
    static var pinyinCorrection: Bool { bool(SettingKey.pinyinCorrection, default: true) }
    static var wubiCorrection: Bool { bool(SettingKey.wubiCorrection, default: true) }

    /// Unknown ids are dropped (SettingsValidation).
    static var fuzzyPinyin: [FuzzyPinyin] {
        guard let raw = Paths.sharedDefaults.object(forKey: SettingKey.fuzzyPinyin) else {
            return FuzzyPinyin.defaults
        }
        return SettingsValidation.fuzzyPinyin(raw)
    }

    /// Invalid entries are dropped (SettingsValidation).
    static var manualPhrases: [ManualPhrase] {
        SettingsValidation.manualPhrases(Paths.sharedDefaults.object(forKey: SettingKey.manualPhrases))
    }

    /// Only a real Bool counts; anything else falls back to the default.
    private static func bool(_ key: String, default value: Bool) -> Bool {
        Paths.sharedDefaults.object(forKey: key) as? Bool ?? value
    }
}

/// What the input method wants Settings to do when it starts it. Launch
/// arguments do not work: the input method is sandboxed, and macOS drops
/// NSWorkspace.OpenConfiguration.arguments from sandboxed callers (seen
/// 2026-11-10: Settings started without `--check-updates` and showed its
/// window while the user was typing). So the input method writes the request
/// here just before starting Settings, and Settings takes it (reads and
/// removes it) at launch. Requests older than `maxAge` are ignored, so a
/// stale one never turns a later manual launch into a background check.
enum SettingsLaunchRequest: String {
    case checkUpdates = "check-updates"
    /// 新手引导 (first time the input method is used).
    case welcome
    case pageGeneral = "page:general"
    case pageModels = "page:models"
    case pageAbout = "page:about"

    private static let key = "settingsLaunchRequest"
    private static let atKey = "settingsLaunchRequestAt"
    static let maxAge: TimeInterval = 30

    /// Input method, right before NSWorkspace.openApplication.
    func post() {
        let defaults = Paths.sharedDefaults
        defaults.set(rawValue, forKey: Self.key)
        defaults.set(Date(), forKey: Self.atKey)
    }

    /// Settings, once at launch. nil: no (fresh, valid) request.
    static func take() -> SettingsLaunchRequest? {
        let defaults = Paths.sharedDefaults
        let raw = defaults.string(forKey: key)
        let at = defaults.object(forKey: atKey) as? Date
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: atKey)
        guard let raw, let at, abs(at.timeIntervalSinceNow) < maxAge else { return nil }
        return SettingsLaunchRequest(rawValue: raw)
    }
}

/// Darwin notification names (Settings → input method).
enum SharedNotifications {
    static let redeployRime = "com.codamon.ergou.redeploy-rime"
    static let clearUserDictionary = "com.codamon.ergou.clear-user-dictionary"
    static let clearVoiceHistory = "com.codamon.ergou.clear-voice-history"

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }

    /// Observe a Darwin notification on the main queue. Keep the returned token alive.
    static func observe(_ name: String, _ handler: @escaping () -> Void) -> NSObjectProtocol {
        let box = HandlerBox(handler)
        let pointer = Unmanaged.passUnretained(box).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), pointer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let box = Unmanaged<HandlerBox>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { box.handler() }
            },
            name as CFString, nil, .deliverImmediately)
        return box
    }

    private final class HandlerBox: NSObject {
        let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
        deinit {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(), nil, nil)
        }
    }
}
