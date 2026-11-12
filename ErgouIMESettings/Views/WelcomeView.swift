// ErgouIME Settings — 新手引导: input scheme, recommended downloads, personal dictionary, voice.
// SPDX-License-Identifier: GPL-3.0-only
//
// Shown once, the first time the input method is used (WelcomeLauncher →
// SettingsLaunchRequest.welcome), and from 关于 › 新手引导. Every step can be
// skipped. Downloads: the page lists, for each item, its name, size, source,
// licence and SHA-256 (under 详情); pressing 下载 is the confirmation
// (Shared/Privacy.swift rule 3). Items then download one after another with
// the same downloader and checks as the 输入 and 语音 pages.

import Combine
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var router: PageRouter
    @State private var step = 0
    private let steps = ["输入方式", "下载", "个人词库", "语音"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                ForEach(steps.indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        Image(systemName: i < step ? "checkmark.circle.fill" : (i == step ? "\(i + 1).circle.fill" : "\(i + 1).circle"))
                            .foregroundStyle(i <= step ? Color.accentColor : Color.secondary)
                        Text(steps[i]).foregroundStyle(i == step ? .primary : .secondary)
                    }
                }
            }
            .padding(.vertical, 14)
            Divider()
            Group {
                switch step {
                case 0: WelcomeSchemeStep()
                case 1: WelcomeDownloadStep()
                case 2: WelcomeDictionaryStep()
                default: WelcomeVoiceStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            HStack {
                Button("跳过引导") { finish() }
                Spacer()
                if step > 0 { Button("上一步") { step -= 1 } }
                if step < steps.count - 1 {
                    Button("下一步") { step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("完成") { finish() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .onAppear { Paths.sharedDefaults.set(true, forKey: SettingKey.welcomeShown) }
    }

    private func finish() {
        router.page = .general
        router.showWelcome = false
    }
}

// MARK: - 1. 输入方式

private struct WelcomeSchemeStep: View {
    @AppStorage(SettingKey.inputScheme, store: Paths.sharedDefaults)
    private var schemeRaw = InputScheme.default.rawValue

    var body: some View {
        Form {
            Section {
                Text("欢迎使用二狗输入法").font(.title2).bold()
                Text("打的字和说的话默认都只在这台 Mac 上处理。花一分钟设置一下：选输入方式、下载推荐的词库和模型、搬来原来的词。每一步都可以跳过，以后在设置里都能改。")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Picker(selection: $schemeRaw) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("拼音")
                        Text("整句输入、简拼（zg → 中国）、模糊音、容错；双拼在设置里选。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(InputScheme.pinyin.rawValue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("五笔拼音混输")
                        Text("五笔 86 优先，不用切换就能打拼音，拼音候选注着五笔码。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(InputScheme.wubiMixed.rawValue)
                } label: { EmptyView() }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .noFocusRing()
                .onChange(of: schemeRaw) { _ in SharedNotifications.post(SharedNotifications.redeployRime) }
            } header: {
                Text("你平时怎么打字？")
            } footer: {
                Text("中文 / 英文用 Shift 切换；英文标点、全角、简繁在菜单栏的输入法菜单里。")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 2. 下载

@MainActor
final class WelcomeDownloads: ObservableObject {
    static let recommended: [SpeechModel] = [
        ModelCatalog.pinyinDictionary, ModelCatalog.grammarCompact,
        ModelCatalog.qwen3ASR06BInt8, ModelCatalog.senseVoiceSmallInt8,
    ]

    let downloader = ModelDownloader()
    @Published var selected: Set<String>
    @Published private(set) var current: SpeechModel?
    /// id → nil (installed now) or an error message.
    @Published private(set) var results: [String: String?] = [:]
    @Published private(set) var running = false
    private var queue: [SpeechModel] = []
    private var watch: AnyCancellable?

    init() {
        selected = Set(Self.recommended.filter { !$0.isInstalled }.map(\.id))
        watch = downloader.$phase.sink { [weak self] phase in
            // Not inside the publisher's own update.
            DispatchQueue.main.async { self?.changed(phase) }
        }
    }

    var pendingBytes: Int64 {
        Self.recommended.filter { selected.contains($0.id) && !$0.isInstalled }.map(\.archiveBytes).reduce(0, +)
    }

    func start() {
        queue = Self.recommended.filter { selected.contains($0.id) && !$0.isInstalled }
        results = [:]
        running = !queue.isEmpty
        next()
    }

    func cancel() {
        queue.removeAll()
        downloader.cancel()
        current = nil
        running = false
    }

    private func next() {
        guard !queue.isEmpty else { current = nil; running = false; return }
        let model = queue.removeFirst()
        current = model
        downloader.start(model)
    }

    private func changed(_ phase: ModelDownloader.Phase) {
        guard let model = current else { return }
        switch phase {
        case .done:
            results[model.id] = .some(nil)
            downloader.reset()
            next()
        case let .failed(message):
            results[model.id] = .some(message)
            downloader.reset()
            next()
        default:
            break
        }
    }
}

private struct WelcomeDownloadStep: View {
    @StateObject private var downloads = WelcomeDownloads()

    var body: some View {
        Form {
            Section {
                ForEach(WelcomeDownloads.recommended) { model in
                    WelcomeDownloadRow(model: model, downloads: downloads)
                }
            } header: {
                Text("推荐下载")
            } footer: {
                Text("安装包里不带词库和模型。点“下载”就是同意从上面写的地址下载这些文件（来源、许可证和 SHA-256 在“详情”里）；下载时不发送其他任何数据，下载后校验 SHA-256。语音模型较大，也可以以后在 设置 › 语音 里再下。")
            }
            Section {
                HStack {
                    if downloads.running {
                        if let current = downloads.current {
                            ProgressRow(model: current, downloader: downloads.downloader)
                        }
                        Spacer()
                        Button("停止", role: .cancel) { downloads.cancel() }
                    } else {
                        Text(downloads.pendingBytes > 0
                             ? "选中的共 \(ByteCountFormatter.string(fromByteCount: downloads.pendingBytes, countStyle: .file))"
                             : "选中的都已经装好了")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("下载") { downloads.start() }
                            .disabled(downloads.pendingBytes == 0)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct WelcomeDownloadRow: View {
    let model: SpeechModel
    @ObservedObject var downloads: WelcomeDownloads
    @State private var details = false

    var body: some View {
        let installed = model.isInstalled
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { installed || downloads.selected.contains(model.id) },
                set: { on in if on { downloads.selected.insert(model.id) } else { downloads.selected.remove(model.id) } })) {
                HStack(spacing: 6) {
                    Text(model.shortName).fontWeight(.medium)
                    Text(ByteCountFormatter.string(fromByteCount: model.archiveBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                    if installed {
                        Label("已安装", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    } else if let result = downloads.results[model.id] {
                        if let error = result {
                            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                        } else {
                            Label("已安装", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                        }
                    }
                }
            }
            .toggleStyle(.checkbox)
            .disabled(installed || downloads.running)
            if let blurb = model.blurb {
                Text(blurb).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
            // The whole "详情" line toggles (a DisclosureGroup only reacts to
            // its small arrow, and centred its content: user report 2026-11-11).
            Button {
                details.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(details ? 90 : 0))
                        .font(.caption2.weight(.semibold))
                    Text("详情")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 3)
                .padding(.trailing, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            if details {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName)
                    // One line; long URLs elide in the middle (they wrapped
                    // mid-path), the full address is in the tooltip.
                    Text("来源：\(model.sourceURL.absoluteString)")
                        .lineLimit(1).truncationMode(.middle)
                        .help(model.sourceURL.absoluteString)
                        .textSelection(.enabled)
                    if let origin = model.originURL {
                        Text("原始来源：\(origin.absoluteString)（二狗存的原样拷贝）")
                            .lineLimit(1).truncationMode(.middle)
                            .help(origin.absoluteString)
                            .textSelection(.enabled)
                    }
                    Text("SHA-256：\(model.sha256)").font(.caption.monospaced())
                        .lineLimit(1).truncationMode(.middle)
                        .help(model.sha256)
                        .textSelection(.enabled)
                    HStack {
                        Text("许可证：\(model.licenseName)")
                        Link("全文", destination: model.licenseURL)
                    }
                    if let note = model.sizeNote { Text(note) }
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 36)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ProgressRow: View {
    let model: SpeechModel
    @ObservedObject var downloader: ModelDownloader

    var body: some View {
        switch downloader.phase {
        case let .downloading(received, total):
            ProgressView(value: Double(received), total: Double(max(total, 1))) {
                Text("正在下载\(model.shortName) \(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                    .font(.caption).monospacedDigit()
            }
            .frame(maxWidth: 360)
        default:
            ProgressView { Text("正在校验和安装\(model.shortName)…").font(.caption) }
                .frame(maxWidth: 360)
        }
    }
}

// MARK: - 3. 个人词库

private struct WelcomeDictionaryStep: View {
    var body: some View {
        Form {
            Section {
                PersonalDictionaryRow()
            } header: {
                Text("把原来的词搬过来")
            } footer: {
                Text("在原来的输入法设置里找“词库”→“导出”或“备份”，导出成 .txt 文本（搜狗的 .scel / .bin 是二进制，读不了）。人名、公司名、专业词搬过来后，打字马上就顺手。没有可以跳过。")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 4. 语音

private struct WelcomeVoiceStep: View {
    @State private var tryText = ""
    @State private var globalStatus = Paths.sharedDefaults.string(forKey: SettingKey.globalVoiceStatus) ?? ""

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Keycap(text: Shortcuts.read().voice.title)
                } label: {
                    Text("点一下开始说话，再点一下结束")
                    Text("在本机识别，直接打进当前的输入框。第一次说话时系统会问麦克风权限，选“允许”。")
                }
                if globalStatus == "needsPermission" || globalStatus == "failed" {
                    LabeledContent {
                        Button("允许…") { InputMonitoringPrompt.ask() }
                    } label: {
                        Text("在别的输入法下也能说话")
                        Text("需要“输入监控”权限，只用来看\(Shortcuts.read().voice.title)有没有被按下，不记录任何按键。")
                    }
                }
            } header: {
                Text("语音输入")
            }
            Section {
                TextField("切到二狗输入法，在这里打几个字，或者点一下\(Shortcuts.read().voice.title)说句话", text: $tryText, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("试一试")
            } footer: {
                Text("以后在菜单栏的输入法菜单 › 打开设置… 里改设置；设置 › 联网记录 里能看到二狗的每一次联网。")
            }
        }
        .formStyle(.grouped)
    }
}
