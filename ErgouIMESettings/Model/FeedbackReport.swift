// ErgouIME Settings — 反馈问题: the environment block for a bug report.
// SPDX-License-Identifier: GPL-3.0-only
//
// There is no telemetry, so a report is the only way we learn about a
// problem. This builds a plain-text summary that the user READS FIRST
// (FeedbackView) and then either opens as a GitHub issue draft in the
// browser or copies. Nothing is sent from here: opening the issue page is
// the browser's request, made after the user clicks, and the user submits
// it there (or not).
//
// What goes in: versions, macOS, Mac model, memory, which options are on,
// which dictionaries and models are installed. What never goes in: anything
// typed or said, word lists (我的词, 常用语, 导入的词 — not even counts),
// microphone names (often the owner's name), cloud addresses and keys,
// file paths (they contain the user name).

import Carbon
import Foundation

enum FeedbackReport {
    static let repository = UpdateChecker.repository

    /// The environment block, one "key: value" per line.
    static func environment() -> String {
        var lines: [(String, String)] = []
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        lines.append(("二狗输入法", "\(version) (\(build))"))
        let os = ProcessInfo.processInfo.operatingSystemVersion
        lines.append(("macOS", "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"))
        lines.append(("Mac", "\(sysctlString("hw.model") ?? "?") · \(architecture) · \(ProcessInfo.processInfo.physicalMemory >> 30) GB"))
        lines.append(("二狗输入源", inputSourceSummary))

        // 输入
        let scheme = SharedSettings.inputScheme
        lines.append(("输入方式", scheme == .pinyin ? "拼音（\(SharedSettings.shuangpin.label)）" : "五笔拼音混输"))
        lines.append(("候选个数", "\(SharedSettings.candidateCount)"))
        lines.append(("自动调频", onOff(SharedSettings.frequencyLearning)))
        lines.append(("联想", onOff(SharedSettings.prediction)))
        let fuzzy = SharedSettings.fuzzyPinyin
        lines.append(("模糊音", fuzzy.isEmpty ? "关" : fuzzy.map(\.rawValue).joined(separator: ",")))
        lines.append(("拼音容错", onOff(SharedSettings.pinyinCorrection)))
        if scheme == .wubiMixed {
            lines.append(("五笔容错", onOff(SharedSettings.wubiCorrection)))
            lines.append(("四码唯一自动上屏", SharedSettings.autoCommitUnique
                ? (SharedSettings.autoCommitStrict ? "开（严格）" : "开") : "关"))
        }
        lines.append(("中英之间加空格", onOff(SharedSettings.autoSpace)))
        lines.append(("拼音大词库", installed(ModelCatalog.pinyinDictionary)
            + (ModelCatalog.pinyinDictionaryTencent.isInstalled ? " + 腾讯词库" : "")))
        let grammar = [ModelCatalog.grammarCompact, ModelCatalog.grammarWanxiang].first(where: \.isInstalled)
        lines.append(("整句模型", grammar?.shortName ?? "未安装"))

        // 语音
        let speech = ModelCatalog.all.filter(\.isInstalled).map(\.shortName)
        lines.append(("语音模型", speech.isEmpty ? "未安装" : speech.joined(separator: "、")))
        lines.append(("自动整理", correctionSummary))
        lines.append(("其他输入法下也能用语音", SharedSettings.globalVoice
            ? "开（\(globalVoiceStatus)）" : "关"))
        lines.append(("麦克风", Paths.sharedDefaults.string(forKey: SettingKey.microphoneUID)?.isEmpty == false
            ? "指定了一个" : (SharedSettings.preferBuiltInMic ? "自动（蓝牙耳机时用内置）" : "自动")))
        lines.append(("语音记录", onOff(SharedSettings.voiceHistoryEnabled)))
        lines.append(("自动检查更新", onOff(SharedSettings.automaticUpdateChecks)))

        return lines.map { "\($0.0)：\($0.1)" }.joined(separator: "\n")
    }

    /// The issue body: questions for the user, then the environment block.
    static func issueBody(environment: String) -> String {
        """
        ## 遇到了什么问题

        （请描述。不要贴密码、验证码或不想公开的内容，这个页面是公开的。）

        ## 怎么出现的

        1.
        2.

        ## 应该是什么样

        ## 环境（二狗自动生成，不含打过的字和说过的话）

        ```
        \(environment)
        ```
        """
    }

    /// GitHub's "new issue" page with title and body filled in. The user
    /// edits and submits it there; GitHub asks them to sign in if needed.
    static func issueURL(environment: String) -> URL? {
        var parts = URLComponents(string: "https://github.com/\(repository)/issues/new")
        parts?.queryItems = [
            URLQueryItem(name: "title", value: "[反馈] "),
            URLQueryItem(name: "body", value: issueBody(environment: environment)),
        ]
        return parts?.url
    }

    // MARK: - Pieces

    private static func onOff(_ on: Bool) -> String { on ? "开" : "关" }

    /// Written by the input method (GlobalHotkey).
    private static var globalVoiceStatus: String {
        switch Paths.sharedDefaults.string(forKey: SettingKey.globalVoiceStatus) ?? "" {
        case "on": return "正常"
        case "needsPermission": return "缺少输入监控权限"
        case "failed": return "启动失败"
        case "off": return "输入法还没应用这个设置"
        case "": return "未知"
        case let other: return other
        }
    }

    private static func installed(_ model: SpeechModel) -> String { model.isInstalled ? "已安装" : "未安装" }

    private static var correctionSummary: String {
        switch SharedSettings.voiceCorrection {
        case .apple: return "Apple 设备端模型"
        case .off: return "关闭"
        case .local:
            let m = SharedSettings.localCorrectionModel
            return "本机小模型（\(m.rawValue)，\(m.files.isPresent ? "已安装" : "未安装")）"
        case .cloud:
            // Provider kind and model name only: the address may be a
            // private relay, and the key never leaves its file.
            let d = Paths.sharedDefaults
            let provider = CloudProvider(rawValue: d.string(forKey: SettingKey.cloudProvider) ?? "") ?? .anthropic
            let modelKey = provider == .anthropic ? SettingKey.cloudModelAnthropic : SettingKey.cloudModelOpenAI
            let model = (d.string(forKey: modelKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = provider == .anthropic ? "Anthropic" : "OpenAI 兼容"
            return "云端（\(name)\(model.isEmpty ? "" : "，\(model.prefix(60))")）"
        }
    }

    private static var architecture: String {
        #if arch(arm64)
        return "Apple 芯片"
        #else
        return "Intel"
        #endif
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// 二狗's rows in Text Input Sources, as `ErgouIME --list-input-sources`
    /// counts them (normally 2: the input method + one mode). Duplicates
    /// were a real support case (0.4.2).
    private static var inputSourceSummary: String {
        let bundleID = "com.codamon.inputmethod.Ergou"
        let all = (TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
        func text(_ source: TISInputSource, _ key: CFString) -> String {
            guard let raw = TISGetInputSourceProperty(source, key) else { return "-" }
            return "\(Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue())"
        }
        let mine = all.filter {
            text($0, kTISPropertyInputSourceID).hasPrefix(bundleID) || text($0, kTISPropertyBundleID) == bundleID
        }
        let enabled = mine.filter { text($0, kTISPropertyInputSourceIsEnabled) == "1" }
        return "\(mine.count) 个（正常是 2 个），已启用 \(enabled.count) 个"
    }
}
