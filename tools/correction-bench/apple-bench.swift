// ergou-ime — run the correction prompt on Apple's on-device model.
// SPDX-License-Identifier: GPL-3.0-only
// swiftc -O -parse-as-library -o apple-bench apple-bench.swift ../../Shared/CorrectionPrompt.swift
import Foundation
import FoundationModels

@main struct AppleBench {
    static func main() async {
        let samples = try! JSONDecoder().decode([String].self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        guard case .available = SystemLanguageModel.default.availability else {
            print("NOT_READY", SystemLanguageModel.default.availability); return
        }
        for s in samples {
            let session = LanguageModelSession(instructions: CorrectionPrompt.system)
            let t0 = Date()
            do {
                let r = try await session.respond(to: s, options: GenerationOptions(temperature: 0))
                let out = CorrectionPrompt.accept(r.content, for: s) ?? "(rejected → keep original)"
                print(String(format: "[%.2fs] ", Date().timeIntervalSince(t0)) + out)
            } catch { print("[error] \(error)") }
        }
    }
}
