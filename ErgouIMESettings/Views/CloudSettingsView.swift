// ErgouIME Settings — 自动整理 › 云端模型: provider, key, context, 测试连接.
// SPDX-License-Identifier: GPL-3.0-only
//
// Provider settings go to the shared defaults; the key goes to the key file
// (CloudShared/CloudKeyFile.swift), which only this program and ErgouIME
// Cloud use. 测试连接 runs through the input method and ErgouIME Cloud — the
// same path as real dictation — with a fixed sentence (no user data); this
// program makes no request itself.

import Combine
import SwiftUI

struct CloudSettingsRows: View {
    @AppStorage(SettingKey.cloudProvider, store: Paths.sharedDefaults)
    private var providerRaw = CloudProvider.anthropic.rawValue
    @AppStorage(SettingKey.cloudBaseURL, store: Paths.sharedDefaults)
    private var baseURL = ""
    @AppStorage(SettingKey.cloudBaseURLAnthropic, store: Paths.sharedDefaults)
    private var baseURLAnthropic = ""
    @AppStorage(SettingKey.cloudModelAnthropic, store: Paths.sharedDefaults)
    private var modelAnthropic = ""
    @AppStorage(SettingKey.cloudModelOpenAI, store: Paths.sharedDefaults)
    private var modelOpenAI = ""
    @AppStorage(SettingKey.cloudSendContext, store: Paths.sharedDefaults)
    private var sendContext = true
    @AppStorage(SettingKey.cloudWholePass, store: Paths.sharedDefaults)
    private var wholePass = false

    @State private var key = ""
    @State private var keySaved: [CloudProvider: Bool] = [:]
    @State private var keyProblem: String?
    @State private var testID: String?
    @State private var testStarted = Date()
    @State private var testOutcome: (ok: Bool, text: String)?
    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var provider: CloudProvider { CloudProvider(rawValue: providerRaw) ?? .anthropic }

    private var model: Binding<String> {
        provider == .anthropic ? $modelAnthropic : $modelOpenAI
    }

    private var saved: Bool { keySaved[provider] ?? CloudKeyFile.isPresent(provider) }

    private var configProblem: String? {
        if provider == .anthropic, !baseURLAnthropic.trimmingCharacters(in: .whitespaces).isEmpty,
           CloudConfig.validBaseURL(baseURLAnthropic) == nil {
            return "接口地址必须以 https:// 开头，不能带 ? 或 #；留空就用 Anthropic 官方地址。"
        }
        if provider == .openAICompatible {
            if baseURL.trimmingCharacters(in: .whitespaces).isEmpty { return "填写服务地址后才能使用。" }
            if CloudConfig.validBaseURL(baseURL) == nil { return "服务地址必须以 https:// 开头，不能带 ? 或 #。" }
            if modelOpenAI.trimmingCharacters(in: .whitespaces).isEmpty { return "填写模型名后才能使用。" }
        }
        let m = model.wrappedValue.trimmingCharacters(in: .whitespaces)
        if !m.isEmpty, CloudConfig.validModel(m) == nil { return "模型名只能有英文字母、数字和 . _ : / @ -。" }
        if !saved { return "保存 API Key 后才能使用；在那之前只加标点。" }
        return nil
    }

    var body: some View {
        Label {
            Text("识别出的文字会发送到你选的服务整理，录音不会发送。按调用量向你自己的账户计费。")
        } icon: {
            Image(systemName: "exclamationmark.shield").foregroundStyle(.orange)
        }
        .font(.callout)

        Picker("服务", selection: $providerRaw) {
            Text("Anthropic（Claude）").tag(CloudProvider.anthropic.rawValue)
            Text("OpenAI 兼容接口").tag(CloudProvider.openAICompatible.rawValue)
        }
        .onChange(of: providerRaw) { _ in key = ""; keyProblem = nil; testOutcome = nil }

        if provider == .anthropic {
            LabeledContent {
                TextField("", text: $baseURLAnthropic, prompt: Text("https://api.anthropic.com（可不填）"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            } label: {
                Text("接口地址")
                Text("可不填。用兼容 Anthropic 接口的转发服务时填到 /v1 为止，后面自动加 /messages；文字会发给这个地址。只能用 https。")
            }
        }
        if provider == .openAICompatible {
            LabeledContent {
                TextField("", text: $baseURL, prompt: Text("https://api.example.com/v1"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            } label: {
                Text("服务地址")
                Text("到 /v1 为止，后面自动加 /chat/completions。只能用 https。")
            }
        }
        LabeledContent("模型") {
            TextField("", text: model, prompt: Text(provider.defaultModel.isEmpty ? "模型名" : provider.defaultModel))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
        }

        LabeledContent {
            HStack {
                SecureField("", text: $key, prompt: Text(saved ? "已保存（重新填写可替换）" : (provider == .anthropic ? "sk-ant-…" : "API Key")))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button(saved ? "替换" : "保存") { saveKey() }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if saved {
                    Button("删除", role: .destructive) {
                        CloudKeyFile.delete(provider)
                        keySaved[provider] = false
                        testOutcome = nil
                    }
                }
            }
        } label: {
            Text("API Key")
            Text(keyProblem ?? "只存在这台 Mac 上（App Group 目录里的私有文件），输入法本身不读它。")
        }

        Toggle(isOn: $sendContext) {
            Text("把光标前的文字一起发送（帮助判断同音字）")
            Text("开始说话时取光标前最多 200 个字，和这次已经说完的前几段一起作为上文发送（合起来最多 200 字），只用来判断同音字和专有词，不会被改动。密码框、终端和密码管理器里不取光标前的文字。关掉后只发送识别出的文字、前几段、当前 App 的名字和我的词。")
        }

        Toggle(isOn: $wholePass) {
            HStack(spacing: 6) {
                Text("说完后再整理一遍全文")
                // Experimental: the rule was tuned on a handful of sentences.
                Text("Beta")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .accessibilityLabel("试验功能")
            }
            Text("试验功能。话是按停顿一段一段整理的，所以说了一半停下、下一段又重说的内容去不掉。打开后，分成两段以上的话在说完后把整段再发一次，只去掉这种重说。代价：每次说完多等 1～2 秒（按回车可以跳过）；模型判断错时，可能删掉你想保留的一句。")
        }

        LabeledContent {
            Button(testID == nil ? "测试连接" : "测试中…") { startTest() }
                .disabled(testID != nil || configProblem != nil)
        } label: {
            Text("测试连接")
            Text("发一句固定的短句，看能不能连上、要多久。")
        }
        .onReceive(poll) { _ in checkTest() }

        if let outcome = testOutcome {
            CloudStatusLine(ok: outcome.ok, text: outcome.text)
        }

        if let problem = configProblem {
            CloudStatusLine(ok: false, text: problem)
        } else {
            CloudStatusLine(ok: true, text: "已就绪。边说边整理：每说完一段（停顿处）就发出去，说完后一般只等最后一段，1–2 秒；说完后最多等 \(Int(CloudTidy.finishWait)) 秒，还没回来的段直接用识别结果。整理中按 ↩ 或右 Option 跳过：已整理好的段用整理结果，其余用识别结果。云端挑出的人名、产品名和术语会存进本机的「我的词」。")
        }
    }

    private func saveKey() {
        if CloudKeyFile.valid(key) == nil {
            keyProblem = "这不像是 API Key（8–512 个英文字符，不能有空格）。"
            return
        }
        let ok = CloudKeyFile.save(key, for: provider)
        keySaved[provider] = ok
        keyProblem = ok ? nil : "没能保存 Key。"
        if ok { key = "" }
    }

    private func startTest() {
        let id = UUID().uuidString
        let d = Paths.sharedDefaults
        d.removeObject(forKey: SettingKey.cloudTestResult)
        d.set(id, forKey: SettingKey.cloudTestRequest)
        testID = id
        testStarted = Date()
        testOutcome = nil
        SharedNotifications.post(SharedNotifications.cloudTest)
    }

    private func checkTest() {
        guard let id = testID else { return }
        if let raw = Paths.sharedDefaults.string(forKey: SettingKey.cloudTestResult),
           let result = try? JSONDecoder().decode(CloudTestResult.self, from: Data(raw.utf8)),
           result.id == id {
            testID = nil
            testOutcome = Self.describe(result.reply)
        } else if Date().timeIntervalSince(testStarted) > CloudTidy.timeout + 6 {
            testID = nil
            testOutcome = (false, "输入法没有响应。先切换到二狗输入法（或打开“在其他输入法下也能用”）再试。")
        }
    }

    static func describe(_ r: CloudTidy.Reply) -> (ok: Bool, text: String) {
        let seconds = String(format: "%.1f", Double(r.ms) / 1000)
        if let text = r.text {
            let terms = r.terms.map(\.term).joined(separator: "、")
            return (true, "连接成功，用时 \(seconds) 秒。整理结果：\(text)" + (terms.isEmpty ? "" : "（挑出的词：\(terms)）"))
        }
        switch r.failure {
        case .noKey?: return (false, "服务读不到 API Key，请重新保存。")
        case .badConfig?: return (false, "服务地址或模型名无效。")
        case .timeout?: return (false, "超过 \(Int(CloudTidy.timeout)) 秒没有返回。")
        case .network?: return (false, "连不上服务器（网络或地址有问题）。")
        case .refused?: return (false, "服务返回了空结果或拒绝处理（HTTP \(r.status)）。")
        case .badJSON?: return (false, "服务的返回不是约定的 JSON，这个模型可能不合适。")
        case .rejected?: return (false, "返回的文字和原文差得太多，没有采用。")
        case .badRequest?: return (false, "请求无效。")
        case .cancelled?: return (false, "请求被取消了。")
        case .http?, nil:
            switch r.status {
            case 401, 403: return (false, "Key 无效或没有权限（HTTP \(r.status)）。")
            case 404: return (false, "地址或模型名不对（HTTP 404）。")
            case 429: return (false, "请求太多或额度用完（HTTP 429）。")
            default: return (false, "服务出错（HTTP \(r.status)）。")
            }
        }
    }
}

private struct CloudStatusLine: View {
    let ok: Bool
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .font(.callout)
    }
}
