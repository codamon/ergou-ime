// ergou-ime — voice correction: XPC interface and local model choices.
// SPDX-License-Identifier: GPL-3.0-only
//
// The input method asks ErgouIME Corrector (XPC service inside
// ErgouIME.app/Contents/XPCServices) to clean up recognised text. The
// service is sandboxed with no network; it loads models from the App Group
// container after checking their SHA-256 (fixed here, not read from disk).

import Foundation

enum CorrectorService {
    static let name = "com.codamon.inputmethod.Ergou.Corrector"
}

@objc protocol CorrectorXPC {
    /// Load the model ahead of time (called when recording starts).
    func prepare(engine: String, model: String, reply: @escaping (Bool) -> Void)
    /// Corrected text, or nil (unavailable, timed out, output rejected).
    func correct(_ text: String, engine: String, model: String, timeout: Double,
                 reply: @escaping (String?) -> Void)
}

/// Local open models for VoiceCorrection.local (D's Mac, 2026-11-09):
/// Qwen2.5-7B fixes most homophones (0.3–1.2 s per sentence, 4 s first
/// load); Qwen3-4B is lighter but fixes fewer.
enum LocalCorrectionModel: String, CaseIterable, Identifiable {
    case qwen25_7b = "qwen2.5-7b"
    case qwen3_4b = "qwen3-4b"

    var id: String { rawValue }

    var files: SpeechModelFiles {
        switch self {
        case .qwen25_7b:
            return SpeechModelFiles(directoryName: "llm-qwen2.5-7b", files: [
                // bartowski/Qwen2.5-7B-Instruct-GGUF (Apache-2.0, Qwen), LFS oid.
                Self.qwen25File: "65b8fcd92af6b4fefa935c625d1ac27ea29dcb6ee14589c55a8f115ceaaa1423",
            ])
        case .qwen3_4b:
            return SpeechModelFiles(directoryName: "llm-qwen3-4b", files: [
                // Qwen/Qwen3-4B-GGUF (Apache-2.0), LFS oid.
                Self.qwen3File: "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5",
            ])
        }
    }

    var fileName: String { self == .qwen25_7b ? Self.qwen25File : Self.qwen3File }

    static let qwen25File = "Qwen2.5-7B-Instruct-Q4_K_M.gguf"
    static let qwen3File = "Qwen3-4B-Q4_K_M.gguf"

    /// 7B on Macs with 16 GB or more, else 4B.
    static var recommended: LocalCorrectionModel {
        ProcessInfo.processInfo.physicalMemory >= 16 << 30 ? .qwen25_7b : .qwen3_4b
    }
}

extension SettingKey {
    /// String raw value of LocalCorrectionModel, default .recommended.
    static let localCorrectionModel = "localCorrectionModel"
}

extension SharedSettings {
    static var localCorrectionModel: LocalCorrectionModel {
        LocalCorrectionModel(rawValue: Paths.sharedDefaults.string(forKey: SettingKey.localCorrectionModel) ?? "")
            ?? .recommended
    }
}
