// ergou-ime — run the correction prompt on a local GGUF model via llama.cpp.
// SPDX-License-Identifier: GPL-3.0-only
import Foundation
let samples = try! JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
let t0 = Date()
guard let c = LlamaCorrector(modelPath: CommandLine.arguments[1]) else { print("load failed"); exit(1) }
print(String(format: "load %.2fs", Date().timeIntervalSince(t0)))
for s in samples {
  let t = Date()
  let r = c.correct(s, timeout: 5)
  print(String(format: "[%.2fs] ", Date().timeIntervalSince(t)) + (r ?? "(rejected → keep original)"))
}
