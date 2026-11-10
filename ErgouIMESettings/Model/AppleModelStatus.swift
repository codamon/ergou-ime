// ErgouIME Settings — is Apple's on-device model usable on this Mac?
// SPDX-License-Identifier: GPL-3.0-only
//
// Foundation Models exists from macOS 26; the framework is weak-linked
// (project.yml) so Settings still runs on macOS 13–15.

import AppKit
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class AppleModelStatus: ObservableObject {
    enum State {
        case unknown, available, notEnabled, notReady, notEligible, oldSystem

        var message: String {
            switch self {
            case .unknown: return "正在检查…"
            case .available: return "可以使用。"
            case .notEnabled: return "Apple 智能没有打开。打开后系统会在后台下载模型。"
            case .notReady: return "Apple 智能现在用不了：可能还在下载模型，也可能是 Siri 语言或地区不支持（例如“中文（中国大陆）”下系统不提供 Apple 智能）。已下载本机小模型时会自动改用它。"
            case .notEligible: return "这台 Mac 不支持 Apple 智能。可以改用本机小模型或云端模型。"
            case .oldSystem: return "需要 macOS 26 或更新版本。可以改用本机小模型或云端模型。"
            }
        }

        var needsSettings: Bool { self == .notEnabled }

        var rowState: RowState {
            switch self {
            case .available: return .ok
            case .unknown: return .pending
            case .notReady: return .warning
            case .notEnabled, .notEligible, .oldSystem: return .warning
            }
        }

        enum RowState { case ok, warning, pending }
    }

    @Published private(set) var state: State = .unknown

    func refresh() {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                state = .available
            case .unavailable(.appleIntelligenceNotEnabled):
                state = .notEnabled
            case .unavailable(.modelNotReady):
                state = .notReady
            case .unavailable(.deviceNotEligible):
                state = .notEligible
            default:
                state = .notReady
            }
            return
        }
        #endif
        state = .oldSystem
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
