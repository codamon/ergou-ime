// ErgouIME Settings — 语音: voice key, microphone, models, correction.
// SPDX-License-Identifier: GPL-3.0-only
//
// Downloads start only after the user confirms the dialog (Privacy rule 3);
// ModelDownloader does the download, checks and install. The cloud
// correction option is the only feature that sends text off the Mac; it is
// off unless the user picks it and enters a key (CloudSettingsView.swift).

import SwiftUI

struct ModelSettingsView: View {
    @AppStorage(SettingKey.preferBuiltInMic, store: Paths.sharedDefaults)
    private var preferBuiltInMic = true
    @AppStorage(SettingKey.microphoneUID, store: Paths.sharedDefaults)
    private var microphoneUID = ""
    @AppStorage(SettingKey.microphoneName, store: Paths.sharedDefaults)
    private var microphoneName = ""
    @StateObject private var microphones = MicrophoneList()
    @AppStorage(SettingKey.globalVoice, store: Paths.sharedDefaults)
    private var globalVoice = true
    /// Written by the input method; polled because it changes in another process.
    @State private var globalStatus = Paths.sharedDefaults.string(forKey: SettingKey.globalVoiceStatus) ?? ""
    private let statusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @AppStorage(SettingKey.voiceHistoryEnabled, store: Paths.sharedDefaults)
    private var historyEnabled = true
    @State private var confirmClearHistory = false
    @AppStorage(SettingKey.learnFromEdits, store: Paths.sharedDefaults)
    private var learnFromEdits = true
    @AppStorage(SettingKey.voiceCorrection, store: Paths.sharedDefaults)
    private var correctionRaw = VoiceCorrection.apple.rawValue

    @EnvironmentObject private var router: PageRouter
    @State private var pending: SpeechModel?
    @StateObject private var downloader = ModelDownloader()
    @State private var refresh = 0

    /// Picking the "未连接" row again keeps the remembered device as is.
    private var micSelection: Binding<String> {
        Binding(get: { microphoneUID }, set: { uid in
            guard uid != microphoneUID else { return }
            SharedSettings.chooseMicrophone(microphones.inputs.first { $0.uid == uid })
        })
    }

    private var globalDetail: String {
        switch globalStatus {
        case "on": return "用拼音、英文或别的输入法时，点右 Option 也能说话，说完自动打进去。"
        case "needsPermission": return "还没有权限，现在只在切到二狗输入法时有效。"
        case "failed": return "没能启动，现在只在切到二狗输入法时有效。"
        default: return "用别的输入法时，点右 Option 也能说话。需要「输入监控」权限。"
        }
    }

    private var micDetail: String {
        let now = AudioInputs.effectiveName(chosenUID: microphoneUID, preferBuiltInOverBluetooth: preferBuiltInMic)
        if microphoneUID.isEmpty {
            return "跟随系统的输入设备；合上盖子时不用内置麦克风。" + (now.map { "现在用：\($0)。" } ?? "")
        }
        if microphones.inputs.contains(where: { $0.uid == microphoneUID }) {
            return "一直用这个麦克风。拔掉时自动换一个，插回来又用它。"
        }
        return "没有连接，暂时自动选择" + (now.map { "（现在用：\($0)）" } ?? "") + "。插回来就用它。"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Keycap(text: "右 Option")
                } label: {
                    Text("开始 / 结束")
                    Text("点一下开始说话，再点一下结束。按住 Option 配合别的键不算。")
                }
                Toggle(isOn: $globalVoice) {
                    Text("在其他输入法下也能用")
                    Text(globalDetail)
                }
                .onChange(of: globalVoice) { _ in SharedNotifications.post(SharedNotifications.globalVoiceChanged) }
                .onReceive(statusTimer) { _ in
                    globalStatus = Paths.sharedDefaults.string(forKey: SettingKey.globalVoiceStatus) ?? ""
                }
                if globalVoice, globalStatus == "needsPermission" || globalStatus == "failed" {
                    LabeledContent {
                        Button("允许…") { SharedRequest.requestInputMonitoring.post() }
                    } label: {
                        Text("需要「输入监控」权限")
                        Text("只用来看右 Option 有没有被按下，不记录、不改动任何按键。系统设置里打开「二狗输入法」后回到这里。")
                    }
                }
                LabeledContent {
                    HStack(spacing: 6) { Keycap(text: "Esc"); Text("取消").foregroundStyle(.secondary)
                        Keycap(text: "↩"); Text("跳过整理").foregroundStyle(.secondary) }
                } label: {
                    Text("录音和整理中")
                }
                Picker(selection: micSelection) {
                    Text("自动").tag("")
                    if !microphoneUID.isEmpty, !microphones.inputs.contains(where: { $0.uid == microphoneUID }) {
                        Text("\(microphoneName.isEmpty ? "之前选的麦克风" : microphoneName)（未连接）").tag(microphoneUID)
                    }
                    ForEach(microphones.inputs) { Text($0.name).tag($0.uid) }
                } label: {
                    Text("麦克风")
                    Text(micDetail)
                }
                if microphoneUID.isEmpty {
                    Toggle(isOn: $preferBuiltInMic) {
                        Text("戴蓝牙耳机时用 Mac 内置麦克风")
                        Text("耳机录音会切到通话模式，音质差、识别不准，听歌也会变差。")
                    }
                }
            } header: {
                Text("语音键")
            } footer: {
                Text("有光标就直接打进去，没有光标就复制到剪贴板。说话可以长达 20 分钟，停顿处会自动分段。在其他输入法下说完，会临时切到二狗输入法打字，再切回去。")
            }

            Section {
                Toggle(isOn: $historyEnabled) {
                    Text("保留语音记录")
                    Text("最近 200 条、30 天，只存在输入法自己的目录里，本设置程序也读不到。像密码、验证码、密钥的内容不记。在输入法菜单 › 语音记录 里查看。")
                }
                .onChange(of: historyEnabled) { on in
                    if !on { SharedRequest.clearVoiceHistory.post() }
                }
                LabeledContent {
                    Button("清空…", role: .destructive) { confirmClearHistory = true }
                } label: {
                    Text("已有记录")
                }
                Toggle(isOn: $learnFromEdits) {
                    Text("从我的修改里学习")
                    Text("语音打出来后，你在同一个输入框里把一个词改成别的，二狗会记住这个词，以后听得更准；同样的修改出现两次，以后就自动改对；你把它改回去，就不再自动改。只记“听成什么 → 改成什么”这一对词，存在输入法自己的目录里，不上传。学到的词在“我的词”里，可以删除。")
                }
            } header: {
                Text("语音记录")
            }
            .confirmationDialog("清空语音记录？", isPresented: $confirmClearHistory) {
                Button("清空", role: .destructive) {
                    SharedRequest.clearVoiceHistory.post()
                }
            } message: {
                Text("所有语音记录都会删除，无法恢复。")
            }

            Section {
                ForEach(ModelCatalog.all) { model in
                    ModelRow(model: model, busy: downloader.isBusy) { pending = model }
                        .id("\(model.id)-\(refresh)")
                }
                LabeledContent {
                    Button("编辑…") { router.page = .terms }
                } label: {
                    Text("我的词")
                    Text("让高精度模型认准常说的人名、地名和术语。")
                }
            } header: {
                Text("模型")
            } footer: {
                Text("两个识别模型可以都装：边说边显示用轻量模型，说完后的结果用高精度模型。模型只在你点“下载”并确认后才下载，下载时不发送其他任何数据，下载后校验 SHA-256。安装包里不带模型。")
            }

            CorrectionSection(selection: Binding(
                get: { VoiceCorrection(rawValue: correctionRaw) ?? .apple },
                set: { correctionRaw = $0.rawValue }),
                              busy: downloader.isBusy,
                              refresh: refresh) { pending = $0 }
        }
        .formStyle(.grouped)
        .sheet(item: $pending) { model in
            ModelDownloadConfirmView(model: model, downloader: downloader) {
                pending = nil
                refresh += 1
            }
        }
    }
}

// MARK: - Focus ring

extension View {
    /// The window puts keyboard focus on the first radio option when it
    /// opens, and macOS then draws a blue ring around that option's label,
    /// which reads like a selection (D, 2026-11-09). Radio groups here are
    /// mouse-driven settings; drop the ring (macOS 14+ API; on 13 the
    /// ring stays).
    @ViewBuilder func noFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }
}

// MARK: - Keycap

/// Same look as the voice HUD's keycaps (ErgouIME/UI/Surface.swift).
struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

// MARK: - Model row

private struct ModelRow: View {
    let model: SpeechModel
    let busy: Bool
    let download: () -> Void

    var body: some View {
        let installed = model.files.isPresent
        LabeledContent {
            Button(installed ? "重新下载…" : "下载…", action: download)
                .disabled(busy)
        } label: {
            HStack(spacing: 6) {
                Text(model.shortName)
                if let badge = model.badge {
                    Text(badge)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
            }
            if let blurb = model.blurb { Text(blurb) }
            HStack(spacing: 4) {
                Image(systemName: installed ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(installed ? Color.green : Color.secondary)
                Text(installed ? "已安装" : "未下载 · \(ByteCountFormatter.string(fromByteCount: model.archiveBytes, countStyle: .file))")
            }
        }
    }
}

// MARK: - Correction

private struct CorrectionSection: View {
    @Binding var selection: VoiceCorrection
    let busy: Bool
    let refresh: Int
    let download: (SpeechModel) -> Void
    @StateObject private var apple = AppleModelStatus()

    var body: some View {
        Section {
            Picker(selection: $selection) {
                ForEach(options) { option in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.title)
                        Text(option.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                    .tag(option)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .noFocusRing()

            CorrectionDetail(option: selection, apple: apple, busy: busy, download: download)
                .id(refresh)
        } header: {
            Text("自动整理")
        } footer: {
            Text("识别、加标点之后再交给大模型整理一遍：改正同音字，数字写成阿拉伯数字，说话中途改口（“A，不对，应该是 B”）只留 B，去掉口头禅和重复。不改写意思。")
        }
        .onAppear {
            apple.refresh()
            CloudKey.migrateLegacyKeychainItem()
        }
    }

    /// 本机小模型 is not recommended any more (2026-11-10: Qwen2.5-7B fixed
    /// few errors and introduced new ones). Shown only to those who use it or
    /// have a model downloaded.
    private var options: [VoiceCorrection] {
        let localInUse = selection == .local
            || LocalCorrectionModel.allCases.contains { $0.files.isPresent }
        return VoiceCorrection.allCases.filter { $0 != .local || localInUse }
    }
}

private struct CorrectionDetail: View {
    let option: VoiceCorrection
    @ObservedObject var apple: AppleModelStatus
    let busy: Bool
    let download: (SpeechModel) -> Void
    @AppStorage(SettingKey.localCorrectionModel, store: Paths.sharedDefaults)
    private var localRaw = LocalCorrectionModel.recommended.rawValue

    var body: some View {
        switch option {
        case .apple:
            StatusRow(state: StatusRowState(apple.state.rowState), text: apple.state.message) {
                if apple.state.needsSettings {
                    Button("打开 Apple 智能设置") { AppleModelStatus.openSettings() }
                }
            }
        case .local:
            let local = LocalCorrectionModel(rawValue: localRaw) ?? .recommended
            Picker("模型", selection: $localRaw) {
                ForEach(LocalCorrectionModel.allCases) { m in
                    Text(m.label).tag(m.rawValue)
                }
            }
            ModelRow(model: ModelCatalog.correction(local), busy: busy) {
                download(ModelCatalog.correction(local))
            }
            StatusRow(state: .warning,
                      text: "不推荐：实测本机 7B / 4B 模型改对的很少，还会把对的改错。建议换成云端模型或 Apple 设备端模型。"
                        + (local.files.isPresent ? "" : "下载后才能使用；在那之前只加标点。"))
        case .cloud:
            CloudSettingsRows()
        case .off:
            StatusRow(state: .ok, text: "只加标点，不做其他修改。")
        }
    }
}

private typealias StatusRowState = StatusRowKind

enum StatusRowKind {
    case ok, warning, pending
    init(_ s: AppleModelStatus.State.RowState) {
        switch s { case .ok: self = .ok; case .warning: self = .warning; case .pending: self = .pending }
    }
}

private struct StatusRow<Accessory: View>: View {
    typealias State = StatusRowKind
    let state: State
    let text: String
    @ViewBuilder var accessory: Accessory

    init(state: State, text: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.state = state
        self.text = text
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            accessory
        }
        .font(.callout)
    }

    private var symbol: String {
        switch state {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .pending: return "clock"
        }
    }

    private var color: Color {
        switch state {
        case .ok: return .green
        case .warning: return .orange
        case .pending: return .secondary
        }
    }
}

extension LocalCorrectionModel {
    var label: String {
        switch self {
        case .qwen25_7b: return "标准 · Qwen2.5 7B（4.7 GB，16 GB 内存以上，不推荐）"
        case .qwen3_4b: return "轻量 · Qwen3 4B（2.5 GB，不推荐）"
        }
    }
}

extension VoiceCorrection {
    var title: String {
        switch self {
        case .apple: return "Apple 设备端模型"
        case .local: return "本机小模型（不推荐）"
        case .cloud: return "云端模型"
        case .off: return "关闭"
        }
    }

    var summary: String {
        switch self {
        case .apple: return "系统自带，不用下载，不联网，免费。需要打开 Apple 智能。"
        case .local: return "不推荐。下载一次（2.5 或 4.7 GB），在这台 Mac 上运行，不联网；实测改不准。"
        case .cloud: return "效果最好，还会顺便把专有词记进「我的词」。文字会离开这台 Mac，需要联网和 API 费用。"
        case .off: return "只加标点。"
        }
    }
}

// MARK: - Model confirmation

struct ModelDownloadConfirmView: View {
    let model: SpeechModel
    @ObservedObject var downloader: ModelDownloader
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("下载\(model.shortName)").font(.title2).bold()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow { Text(model.kind).foregroundStyle(.secondary); Text(model.displayName) }
                GridRow {
                    Text("大小").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ByteCountFormatter.string(fromByteCount: model.archiveBytes, countStyle: .file))
                        if let note = model.sizeNote {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                GridRow {
                    Text("来源").foregroundStyle(.secondary)
                    Text(model.sourceURL.absoluteString).font(.caption).textSelection(.enabled)
                        .lineLimit(2).truncationMode(.middle)
                }
                GridRow {
                    Text("SHA-256").foregroundStyle(.secondary)
                    Text(model.sha256).font(.caption.monospaced()).textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("\(model.kind)许可证：\(model.licenseName)").bold()
                ForEach(model.licenseSummary, id: \.self) { line in
                    Text("• " + line).fixedSize(horizontal: false, vertical: true)
                }
                Link("阅读协议全文", destination: model.licenseURL)
                Text(model.attribution).font(.caption).foregroundStyle(.secondary)
            }
            progressView
            HStack {
                Spacer()
                switch downloader.phase {
                case .done:
                    Button("完成") { downloader.reset(); dismiss() }.keyboardShortcut(.defaultAction)
                case .downloading, .verifying, .installing:
                    Button("取消下载", role: .cancel) { downloader.cancel() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(downloader.phase == .verifying || downloader.phase == .installing)
                default:
                    Button("取消", role: .cancel) { downloader.reset(); dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("下载") { downloader.start(model) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    @ViewBuilder private var progressView: some View {
        switch downloader.phase {
        case let .downloading(received, total):
            ProgressView(value: Double(received), total: Double(max(total, 1))) {
                Text("正在下载 \(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                    .font(.caption).monospacedDigit()
            }
        case .verifying, .installing:
            ProgressView { Text("正在校验和安装…").font(.caption) }
        case .done:
            Label(model.installedNote ?? "已安装，马上就能用。", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }
}
