// ErgouIME Settings — about / licences.
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("二狗输入法 Ergou IME", value: version)
                Text("隐私优先的开源 macOS 中文输入法，GPL-3.0。")
                Text("输入法本身从不联网。本设置程序只在你点“下载”或“检查更新”时联网；选了云端整理时，会把识别出的文字发给你选的服务。没有遥测。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    // TODO(M3 T3.7): Sparkle 2; automatic checks default off
                    // (PrivacyPolicy.automaticUpdateChecksDefault).
                    Button("检查更新…") {}.disabled(true)
                } label: {
                    Text("更新")
                    Text("只在你点按钮时联网。")
                }
            }
            Section("第三方组件") {
                ForEach(ThirdParty.components) { c in
                    LabeledContent {
                        Link(destination: c.url) {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                        .help(c.url.absoluteString)
                    } label: {
                        Text(c.name)
                        Text(c.license)
                    }
                }
                // TODO(M6): show full licence texts bundled in Resources/Licenses.
            }
        }
        .formStyle(.grouped)
    }
}

struct ThirdPartyComponent: Identifiable {
    var id: String { name }
    let name: String
    let license: String
    let url: URL
}

enum ThirdParty {
    // Keep in sync with docs/THIRD_PARTY.md.
    static let components: [ThirdPartyComponent] = [
        .init(name: "librime", license: "BSD-3-Clause", url: URL(string: "https://github.com/rime/librime")!),
        .init(name: "rime-prelude", license: "LGPL-3.0", url: URL(string: "https://github.com/rime/rime-prelude")!),
        .init(name: "rime-wubi86-jidian", license: "MIT", url: URL(string: "https://github.com/KyleBing/rime-wubi86-jidian")!),
        .init(name: "雾凇拼音词库（拼音大词库，单独下载）", license: "GPL-3.0", url: URL(string: "https://github.com/iDvel/rime-ice")!),
        .init(name: "sherpa-onnx", license: "Apache-2.0", url: URL(string: "https://github.com/k2-fsa/sherpa-onnx")!),
        .init(name: "onnxruntime", license: "MIT", url: URL(string: "https://github.com/microsoft/onnxruntime")!),
        .init(name: "llama.cpp", license: "MIT", url: URL(string: "https://github.com/ggml-org/llama.cpp")!),
        .init(name: "Qwen2.5 / Qwen3 整理模型（单独下载）", license: "Apache-2.0", url: URL(string: "https://github.com/QwenLM/Qwen3")!),
        .init(name: "Qwen3-ASR 0.6B 高精度识别模型（单独下载）", license: "Apache-2.0", url: URL(string: "https://github.com/QwenLM/Qwen3-ASR")!),
        .init(name: "SenseVoice Small、CT-Transformer 标点模型（单独下载）", license: "FunASR 模型协议",
              url: URL(string: "https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE")!),
        // Sparkle (MIT) is listed here once it ships (M3 T3.7).
    ]
}
