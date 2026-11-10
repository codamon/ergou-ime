// ErgouIME Settings — 输入: scheme, 拼音大词库, mixed input, fuzzy pinyin, typo tolerance.
// SPDX-License-Identifier: GPL-3.0-only
//
// Settings never writes Rime files: every change goes to the shared defaults
// and the input method regenerates its config and redeploys (Privacy rule 9).

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(SettingKey.frequencyLearning, store: Paths.sharedDefaults)
    private var frequencyLearning = PrivacyPolicy.frequencyLearningDefault
    @AppStorage(SettingKey.autoCommitUnique, store: Paths.sharedDefaults)
    private var autoCommitUnique = false
    @AppStorage(SettingKey.autoCommitStrict, store: Paths.sharedDefaults)
    private var autoCommitStrict = false
    @AppStorage(SettingKey.pinyinCorrection, store: Paths.sharedDefaults)
    private var pinyinCorrection = true
    @AppStorage(SettingKey.wubiCorrection, store: Paths.sharedDefaults)
    private var wubiCorrection = true
    @AppStorage(SettingKey.autoSpace, store: Paths.sharedDefaults)
    private var autoSpace = true
    @AppStorage(SettingKey.prediction, store: Paths.sharedDefaults)
    private var prediction = true
    @AppStorage(SettingKey.inputScheme, store: Paths.sharedDefaults)
    private var schemeRaw = InputScheme.default.rawValue
    @State private var fuzzy = Set(SharedSettings.fuzzyPinyin)
    @State private var confirmClear = false
    @State private var pendingDownload: SpeechModel?
    @State private var pendingRemove: SpeechModel?
    @State private var dictRefresh = 0
    @StateObject private var downloader = ModelDownloader()

    @AppStorage(SettingKey.shuangpin, store: Paths.sharedDefaults)
    private var shuangpinRaw = Shuangpin.none.rawValue
    @AppStorage(SettingKey.candidateCount, store: Paths.sharedDefaults)
    private var candidateCount = CandidateCount.default

    private var isWubi: Bool { (InputScheme(rawValue: schemeRaw) ?? .default) == .wubiMixed }

    var body: some View {
        Form {
            Section {
                Picker(selection: $schemeRaw) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("拼音")
                        Text("普通拼音输入法：整句输入、简拼（zg → 中国）、模糊音、容错，也可以用双拼。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(InputScheme.pinyin.rawValue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("五笔拼音混输")
                        Text("五笔优先，拼音候选注着五笔码。会五笔的用这个。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(InputScheme.wubiMixed.rawValue)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .noFocusRing()
                .onChange(of: schemeRaw) { _ in redeploy() }
                if !isWubi {
                    Picker("拼音方案", selection: $shuangpinRaw) {
                        ForEach(Shuangpin.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .onChange(of: shuangpinRaw) { _ in redeploy() }
                }
                Picker(selection: $candidateCount) {
                    ForEach(Array(CandidateCount.range), id: \.self) { Text("\($0) 个").tag($0) }
                } label: {
                    Text("每页候选个数")
                    Text("按数字 1～\(candidateCount) 选词。")
                }
                .onChange(of: candidateCount) { _ in redeploy() }
            } header: {
                Text("输入方式")
            }

            PinyinDictionarySection(busy: downloader.isBusy,
                                    download: { pendingDownload = $0 },
                                    remove: { pendingRemove = $0 })
                .id(dictRefresh)

            Section {
                Toggle(isOn: $frequencyLearning) {
                    Text("自动调频")
                    Text(isWubi
                         ? "常用的字词排到前面。只调整顺序，不会新增词条，也不影响四码唯一自动上屏。"
                         : "常用的字词排到前面，也会记住你打过的词。")
                }
                .onChange(of: frequencyLearning) { _ in redeploy() }
                LabeledContent {
                    Button("清空…", role: .destructive) { confirmClear = true }
                } label: {
                    Text("调频记录")
                    Text("只在本机，不同步。清空后顺序回到码表默认。")
                }
            } header: {
                Text("词频")
            }

            Section {
                Toggle(isOn: $autoSpace) {
                    Text("中英文之间加空格")
                    Text("“用 macOS 开发”而不是“用macOS开发”。打字和语音都适用。")
                }
                Toggle(isOn: $prediction) {
                    Text("联想")
                    Text("上屏后提示接下来可能要打的词，按数字或用鼠标点选；Esc 或接着打字就收起。词库只读，不记录你打的内容。")
                }
            } header: {
                Text("排版")
            } footer: {
                Text("每个应用会记住上次是中文还是英文；终端默认英文。英文标点和全角在输入法菜单里切换。")
            }

            if isWubi {
            Section {
                Toggle(isOn: $autoCommitUnique) {
                    Text("四码唯一自动上屏")
                    Text(autoCommitUnique
                         ? "四个键只对应一个五笔字时直接上屏；接着打下一个字会把第一个候选顶上屏。这几个键也像拼音（如 shan → shang）时，当拼音继续，按空格上屏五笔。"
                         : "关闭时用空格或数字选词。")
                }
                .onChange(of: autoCommitUnique) { _ in redeploy() }
                if autoCommitUnique {
                    Toggle(isOn: $autoCommitStrict) {
                        Text("不等下一个键")
                        Text("四码唯一就立刻上屏。长拼音要先按 ` 再打。")
                    }
                    .onChange(of: autoCommitStrict) { _ in redeploy() }
                }
            } header: {
                Text("五笔拼音混输")
            } footer: {
                Text("候选顺序：五笔码对上的字 → 拼音 → 还没打完的五笔码 → 容错候选。拼音候选旁边注着五笔码。先按 ` 只打拼音。")
            }
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(FuzzyPinyin.allCases) { pair in
                        Toggle(pair.label, isOn: binding(for: pair))
                            .toggleStyle(.checkbox)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("模糊音")
            } footer: {
                Text("开得越多，拼音候选越多；打开四码唯一自动上屏时，要按空格的五笔码也越多。")
            }

            Section {
                Toggle(isOn: $pinyinCorrection) {
                    Text("拼音容错")
                    Text(isWubi
                         ? "常见的字母打反（shagn → shang）也能出字。先按 ` 只打拼音时，按到相邻键也能纠正。"
                         : "常见的字母打反（shagn → shang）、按到相邻的键，都能出字。")
                }
                .onChange(of: pinyinCorrection) { _ in redeploy() }
                if isWubi {
                Toggle(isOn: $wubiCorrection) {
                    Text("五笔容错")
                    Text("打出的码没有任何候选时，试着交换相邻两码或换成相邻键，结果标“纠”，排在最后，不会自动上屏。")
                }
                .onChange(of: wubiCorrection) { _ in redeploy() }
                }
            } header: {
                Text("打错时")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $pendingDownload) { model in
            ModelDownloadConfirmView(model: model, downloader: downloader) {
                pendingDownload = nil
                dictRefresh += 1
            }
        }
        .confirmationDialog("删除\(pendingRemove?.shortName ?? "词库")？",
                            isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
                            presenting: pendingRemove) { model in
            Button("删除", role: .destructive) {
                // 腾讯词库 is only used with 拼音大词库: deleting the latter removes both.
                if model.id == ModelCatalog.pinyinDictionary.id {
                    ModelDownloader.remove(ModelCatalog.pinyinDictionaryTencent)
                }
                ModelDownloader.remove(model)
                dictRefresh += 1
            }
        } message: { model in
            switch model.id {
            case ModelCatalog.pinyinDictionary.id:
                Text("拼音换回自带的小词库（约 8 万词），腾讯词库也一起删除。调频记录和手动加的词不受影响。以后可以再下载。")
            case ModelCatalog.pinyinDictionaryTencent.id:
                Text("拼音继续用拼音大词库，只是少了腾讯词库的约 98 万词。以后可以再下载。")
            default:
                Text("整句输入回到不用模型的方式，内存也会释放。以后可以再下载。")
            }
        }
        .confirmationDialog("清空调频记录？", isPresented: $confirmClear) {
            Button("清空", role: .destructive) {
                SharedNotifications.post(SharedNotifications.clearUserDictionary)
            }
        } message: {
            Text("自动记录的词频都会删除，无法恢复。手动添加的词不受影响。")
        }
    }

    private func binding(for pair: FuzzyPinyin) -> Binding<Bool> {
        Binding(
            get: { fuzzy.contains(pair) },
            set: { on in
                if on { fuzzy.insert(pair) } else { fuzzy.remove(pair) }
                Paths.sharedDefaults.set(FuzzyPinyin.allCases.filter(fuzzy.contains).map(\.rawValue),
                                         forKey: SettingKey.fuzzyPinyin)
                redeploy()
            })
    }

    /// The input method regenerates its Rime files from the shared settings
    /// (after validating them) and redeploys. Settings never writes Rime files.
    private func redeploy() {
        SharedNotifications.post(SharedNotifications.redeployRime)
    }
}

// MARK: - 拼音大词库

/// Download / delete rows for 拼音大词库 and its optional 腾讯词库
/// (ModelCatalog). The input method decides whether to use them (it checks
/// the files again); this only shows whether the files are here.
private struct PinyinDictionarySection: View {
    let busy: Bool
    let download: (SpeechModel) -> Void
    let remove: (SpeechModel) -> Void

    var body: some View {
        let base = ModelCatalog.pinyinDictionary
        let baseInstalled = base.isInstalled
        Section {
            DictionaryRow(model: base, busy: busy, download: download, remove: remove,
                          status: baseInstalled ? "已安装 · 雾凇拼音 2026.06.30"
                              : "未下载 · \(ByteCountFormatter.string(fromByteCount: base.archiveBytes, countStyle: .file))，现在用的是自带的小词库")
            if baseInstalled {
                let tencent = ModelCatalog.pinyinDictionaryTencent
                DictionaryRow(model: tencent, busy: busy, download: download, remove: remove,
                              status: tencent.isInstalled ? "已安装"
                                  : "未下载 · \(ByteCountFormatter.string(fromByteCount: tencent.archiveBytes, countStyle: .file))")
            }
            ForEach([ModelCatalog.grammarCompact, ModelCatalog.grammarWanxiang]) { model in
                DictionaryRow(model: model, busy: busy, download: download, remove: remove,
                              status: model.isInstalled ? "已安装，正在使用"
                                  : "未下载 · \(ByteCountFormatter.string(fromByteCount: model.archiveBytes, countStyle: .file))")
            }
        } header: {
            Text("词库和整句模型")
        } footer: {
            Text("整句模型按词和词的搭配挑整句，长句更准，但会多占内存；两个只能用一个，下载一个会替换另一个。都只在你点“下载”并确认后才从 GitHub 下载，不发送其他任何数据；下载后校验 SHA-256，输入法用之前再校验一遍。")
        }
    }
}

private struct DictionaryRow: View {
    let model: SpeechModel
    let busy: Bool
    let download: (SpeechModel) -> Void
    let remove: (SpeechModel) -> Void
    let status: String

    var body: some View {
        let installed = model.isInstalled
        LabeledContent {
            HStack {
                if installed {
                    Button("删除…", role: .destructive) { remove(model) }.disabled(busy)
                }
                Button(installed ? "重新下载…" : "下载…") { download(model) }.disabled(busy)
            }
        } label: {
            HStack(spacing: 6) {
                Text(model.shortName)
                if !installed, let badge = model.badge {
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
                Text(status)
            }
        }
    }
}
