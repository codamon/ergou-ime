// ErgouIME Settings — 输入: Wubi, mixed input, fuzzy pinyin, typo tolerance.
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
    private var schemeRaw = InputScheme.wubiMixed.rawValue
    @State private var fuzzy = Set(SharedSettings.fuzzyPinyin)
    @State private var confirmClear = false

    @AppStorage(SettingKey.shuangpin, store: Paths.sharedDefaults)
    private var shuangpinRaw = Shuangpin.none.rawValue

    private var isWubi: Bool { (InputScheme(rawValue: schemeRaw) ?? .wubiMixed) == .wubiMixed }

    var body: some View {
        Form {
            Section {
                Picker(selection: $schemeRaw) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("五笔拼音混输")
                        Text("五笔优先，拼音候选注着五笔码。会五笔的用这个。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(InputScheme.wubiMixed.rawValue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("只用拼音")
                        Text("普通拼音输入法：整句输入、简拼（zg → 中国）、模糊音、容错。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(InputScheme.pinyin.rawValue)
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
            } header: {
                Text("输入方式")
            }

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
