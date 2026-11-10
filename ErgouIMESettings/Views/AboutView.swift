// ErgouIME Settings — about / licences.
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct AboutView: View {
    @AppStorage(SettingKey.automaticUpdateChecks, store: Paths.sharedDefaults)
    private var automaticChecks = PrivacyPolicy.automaticUpdateChecksDefault
    @State private var checking = false
    @State private var checkResult: String?

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
                Text("输入法本身从不联网。本设置程序只在你点“下载”“检查更新”，以及每天自动检查一次更新时联网；选了云端整理时，会把识别出的文字发给你选的服务。没有遥测。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $automaticChecks) {
                    Text("自动检查更新")
                    Text("每天最多一次，只问 GitHub 有没有新版本，不发送任何输入内容或设置。有新版本时弹窗问你，同意后才下载和安装。")
                }
                LabeledContent {
                    Button(checking ? "正在检查…" : "检查更新…") { checkNow() }
                        .disabled(checking)
                } label: {
                    Text("现在检查")
                    Text(checkResult ?? lastCheckText)
                }
            } header: {
                Text("更新")
            } footer: {
                Text("安装包核对 SHA-256、开发者签名和苹果公证后，交给系统安装器安装。")
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

    private var lastCheckText: String {
        guard let last = SharedSettings.lastUpdateCheck else { return "还没有检查过。" }
        return "上次检查：" + last.formatted(date: .abbreviated, time: .shortened)
    }

    /// Manual check: shows the update window even for a skipped version.
    private func checkNow() {
        checking = true
        checkResult = nil
        UpdateInstaller.removeOldPackages()
        Task { @MainActor in
            let result = await UpdateChecker.check()
            checking = false
            switch result {
            case let .upToDate(current):
                checkResult = "已经是最新版本（\(current)）。"
            case let .available(update):
                checkResult = "有新版本 \(update.version)。"
                UpdateWindowController.shared.show(update, activate: true)
            case let .failed(message):
                checkResult = message
            }
        }
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
        .init(name: "librime-octagram（整句模型插件）", license: "BSD-3-Clause", url: URL(string: "https://github.com/lotem/librime-octagram")!),
        .init(name: "rime-octagram-data 整句模型 · 轻量（单独下载）", license: "LGPL-3.0", url: URL(string: "https://github.com/lotem/rime-octagram-data")!),
        .init(name: "RIME-LMDG 万象整句模型 © amzxyz（单独下载）", license: "CC BY 4.0", url: URL(string: "https://github.com/amzxyz/RIME-LMDG")!),
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
