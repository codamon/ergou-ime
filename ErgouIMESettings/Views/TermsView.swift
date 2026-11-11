// ErgouIME Settings — 我的词: names and terms the recogniser should get right.
// SPDX-License-Identifier: GPL-3.0-only
//
// Manual terms are saved to the shared defaults (validated here and again
// in the input method). Learned terms are read from the file the input
// method keeps in the App Group container; this program never writes it:
// 删除 / 固定 are requests the input method applies (Shared/VoiceTerms.swift).

import Combine
import SwiftUI

struct TermsView: View {
    @State private var manual = SharedSettings.voiceTermsManual
    @State private var learned = TermsView.loadLearned()
    @State private var draft = ""
    @State private var problem: String?
    @State private var accurateInstalled = SpeechModelFiles.qwen3ASR06BInt8.isPresent
    @EnvironmentObject private var router: PageRouter
    /// The input method updates the file in another process.
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var active: Set<String> {
        Set(VoiceTermRules.effective(manual: manual, learned: learned).map(VoiceTermRules.key))
    }

    var body: some View {
        Form {
            if !accurateInstalled {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("我的词只对高精度识别模型有效。先在 语音 › 模型 里下载它。")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("去下载") { router.page = .models }
                    }
                    .font(.callout)
                }
            }

            Section {
                HStack {
                    TextField("例如：惠灵顿、Claude、右 Option", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("添加", action: add)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                }
                if manual.isEmpty {
                    Text("还没有添加。把常说、但总被认错的人名、地名、产品名、英文术语加进来。")
                        .foregroundStyle(.secondary)
                }
                ForEach(manual, id: \.self) { term in
                    LabeledContent {
                        HStack(spacing: 8) {
                            if !active.contains(VoiceTermRules.key(term)) {
                                Text("超出上限，未生效").font(.caption).foregroundStyle(.secondary)
                            }
                            Button(role: .destructive) { remove(term) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("删除")
                        }
                    } label: {
                        Text(term)
                    }
                }
            } header: {
                Text("手动添加")
            } footer: {
                Text("每个词 1～\(VoiceTermRules.maxLength) 个字，不能是纯数字、邮箱、网址，或像密码、验证码的字符串。最多 \(VoiceTermRules.maxManual) 个。")
            }

            Section {
                if learned.isEmpty {
                    Text("还没有学到的词。自动整理选“云端模型”后，它挑出和改正的名字、术语会记在这里。")
                        .foregroundStyle(.secondary)
                }
                ForEach(learned) { t in
                    LearnedTermRow(term: t, active: active.contains(VoiceTermRules.key(t.term))) {
                        request(TermEdit(t.pinned ? .unpin : .pin, t.term))
                    } delete: {
                        request(TermEdit(.delete, t.term))
                    }
                }
            } header: {
                Text("学到的词")
            } footer: {
                Text("被认错过的词出现 1 次就生效，其他词出现 2 次后生效。固定的词一直生效。删除后不会再自动学。")
            }

            Section {
                LabeledContent("现在生效") {
                    Text("\(active.count) 个").monospacedDigit()
                }
            } footer: {
                Text("识别时会优先认出这些词。手动添加的和固定的排在前面，其余按出现次数和最近使用排序，最多 \(VoiceTermRules.maxActive) 个；词越多，识别越慢一点。我的词存在这台 Mac 上；只有打开云端整理时，才会把其中最多 50 个（不含“你改过”的词）随识别文字发给云端模型。")
            }
        }
        .formStyle(.grouped)
        .onReceive(refresh) { _ in
            let now = Self.loadLearned()
            if now != learned { learned = now }
            accurateInstalled = SpeechModelFiles.qwen3ASR06BInt8.isPresent
        }
    }

    private func add() {
        guard let term = VoiceTermRules.term(draft) else {
            problem = "这个词不能用：要 1～\(VoiceTermRules.maxLength) 个字，至少有一个字或字母，不能有逗号等标点，不能像邮箱、网址或密码。"
            return
        }
        if manual.contains(where: { VoiceTermRules.key($0) == VoiceTermRules.key(term) }) {
            problem = "“\(term)”已经在列表里了。"
            return
        }
        guard manual.count < VoiceTermRules.maxManual else {
            problem = "最多 \(VoiceTermRules.maxManual) 个，先删掉一些。"
            return
        }
        manual.append(term)
        draft = ""
        problem = nil
        saveManual()
    }

    private func remove(_ term: String) {
        manual.removeAll { $0 == term }
        saveManual()
    }

    private func saveManual() {
        SharedSettings.saveVoiceTermsManual(manual)
        SharedNotifications.post(SharedNotifications.voiceTermsChanged)
    }

    private func request(_ edit: TermEdit) {
        SharedSettings.requestTermEdit(edit)
        SharedNotifications.post(SharedNotifications.voiceTermsChanged)
        learned = Self.loadLearned()
    }

    /// Pinned first, then by count × recency (the order they are used in).
    private static func loadLearned() -> [LearnedTerm] {
        let now = Date()
        return SharedSettings.learnedTermsForDisplay.terms.sorted {
            ($0.pinned ? 1 : 0, VoiceTermRules.score($0, now: now)) > ($1.pinned ? 1 : 0, VoiceTermRules.score($1, now: now))
        }
    }
}

private struct LearnedTermRow: View {
    let term: LearnedTerm
    let active: Bool
    let togglePin: () -> Void
    let delete: () -> Void

    private var detail: String {
        var parts = ["出现 \(term.count) 次"]
        if term.source == .edit { parts.insert("你改过", at: 0) }
        if !term.heard.isEmpty { parts.append("听成过：" + term.heard.joined(separator: "、")) }
        if term.pinned { parts.append("已固定") }
        else if active { parts.append("已生效") }
        else if VoiceTermRules.isActive(term) { parts.append("超出上限，未生效") }
        else { parts.append("再出现 \(max(1, 2 - term.count)) 次后生效") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Button(action: togglePin) {
                    Image(systemName: term.pinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.borderless)
                .help(term.pinned ? "取消固定" : "固定：一直生效")
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("删除，以后也不再学")
            }
        } label: {
            Text(term.term)
            Text(detail)
        }
    }
}
