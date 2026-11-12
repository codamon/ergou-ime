// ergou-ime — 说中文出英文: the recognised Chinese to English through
// ErgouIME Cloud (Shared/EnglishVoice.swift has the prompt and checks).
// SPDX-License-Identifier: GPL-3.0-only
//
// One request per chunk (CloudTidy.translateChunks), all sent at once; the
// first chunk takes the text before the cursor as context, each later one
// the end of the Chinese chunk before it. Every chunk must come back:
// half English, half Chinese is worse than either, so one failed chunk
// means the Chinese is typed. Logs counts and timing only, never text.

import Foundation

enum EnglishPass {
    enum Outcome {
        case english(String)
        /// Why not, for the note shown when the Chinese is typed instead.
        case failed(CloudTidy.Failure?)
    }

    /// `done` on the main queue, once.
    static func translate(_ text: String, context: CloudCorrector.Context, terms: [String], batch: Int,
                          done: @escaping (Outcome) -> Void) {
        let chunks = CloudTidy.translateChunks(text)
        guard !chunks.isEmpty else { done(.failed(.badRequest)); return }
        let started = DispatchTime.now()
        var parts = [String?](repeating: nil, count: chunks.count)
        var failure: CloudTidy.Failure?
        var left = chunks.count
        for (i, chunk) in chunks.enumerated() {
            let before = i == 0 ? context.before : CloudTidy.contextTail(chunks[i - 1])
            let request = CloudTidy.Request(text: chunk, context: before, app: context.app, terms: terms,
                                            timeout: CloudTidy.translateTimeout, batch: batch, english: true)
            CloudCorrector.shared.send(request) { reply in          // main queue
                if let t = reply?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    parts[i] = t
                } else if failure == nil {
                    failure = reply?.failure ?? .timeout
                }
                left -= 1
                guard left == 0 else { return }
                let ok = parts.allSatisfy { $0 != nil }
                let ms = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e6
                Log.speech.notice("english: \(parts.compactMap { $0 }.count, privacy: .public)/\(chunks.count, privacy: .public) chunks, \(text.count, privacy: .public) chars in, \(ms, format: .fixed(precision: 0), privacy: .public) ms, \(ok ? "ok" : (failure?.rawValue ?? "failed"), privacy: .public)")
                done(ok ? .english(CloudTidy.joinEnglish(parts.compactMap { $0 })) : .failed(failure))
            }
        }
    }

    /// The HUD line when the Chinese was typed instead.
    static func failureNote(_ failure: CloudTidy.Failure?) -> String {
        switch failure {
        case .noKey: return "没有 API Key，已输入中文"
        case .badConfig:
            return SharedSettings.voiceCorrection == .cloud ? "云端设置不完整，已输入中文" : "说中文出英文要用云端整理，已输入中文"
        case .timeout: return "翻译超时，已输入中文"
        case .network: return "连不上云端服务，已输入中文"
        default: return "没能翻译成英文，已输入中文"
        }
    }
}
