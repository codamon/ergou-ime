// ErgouIME Settings — 常用语.
// SPDX-License-Identifier: GPL-3.0-only
//
// Saved to the shared defaults (validated here and again in the input
// method); the input method writes ergou_phrases.txt for codes and shows
// the list under 输入法菜单 › 常用语….

import SwiftUI

struct PhrasesView: View {
    @State private var phrases = SharedSettings.quickPhrases
    @State private var editing: Editing?

    struct Editing: Identifiable {
        let id = UUID()
        var index: Int?
        var code: String
        var text: String
    }

    var body: some View {
        Form {
            Section {
                if phrases.isEmpty {
                    Text("还没有常用语。点“添加”存一段经常要打的话，比如地址、邮箱、签名。")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(phrases.enumerated()), id: \.element.id) { i, p in
                    LabeledContent {
                        HStack(spacing: 6) {
                            if !p.code.isEmpty { Keycap(text: p.code) }
                            Button("编辑") { editing = Editing(index: i, code: p.code, text: p.text) }
                                .buttonStyle(.borderless)
                            Button(role: .destructive) { remove(i) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("删除")
                        }
                    } label: {
                        Text(p.text.replacingOccurrences(of: "\n", with: " ⏎ ")).lineLimit(2)
                    }
                }
                Button("添加…") { editing = Editing(index: nil, code: "", text: "") }
            } header: {
                Text("常用语")
            } footer: {
                Text("有编码的，打编码就会出现在候选里（五笔模式下排在五笔字后面）。所有常用语都可以在输入法菜单 › 常用语… 里点选插入。最多 \(SettingsValidation.maxQuickPhrases) 条，每条最多 \(SettingsValidation.maxQuickPhraseLength) 字。只存在这台 Mac 上。")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { e in
            PhraseEditor(editing: e) { code, text in
                guard let phrase = SettingsValidation.quickPhrase(code: code, text: text) else { return false }
                if let i = e.index { phrases[i] = phrase } else { phrases.append(phrase) }
                save()
                return true
            } cancel: { editing = nil }
        }
    }

    private func remove(_ i: Int) {
        phrases.remove(at: i)
        save()
    }

    private func save() {
        // The same code and text twice would be one list row twice.
        phrases = SettingsValidation.uniqued(phrases)
        SharedSettings.saveQuickPhrases(phrases)
        editing = nil
        // Only the phrase file changes: no redeploy, typing is not interrupted.
        SharedNotifications.post(SharedNotifications.regeneratePhrases)
    }
}

private struct PhraseEditor: View {
    let editing: PhrasesView.Editing
    let save: (String, String) -> Bool
    let cancel: () -> Void
    @State private var code = ""
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing.index == nil ? "添加常用语" : "编辑常用语").font(.title3).bold()
            TextEditor(text: $text)
                .font(.system(size: 14))
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            HStack {
                Text("编码（可选）")
                TextField("例如 dz", text: $code).frame(width: 120)
                Text("只用字母，最多 8 个").font(.caption).foregroundStyle(.secondary)
            }
            if invalid {
                Label("内容要在 1～500 字之间，不能有制表符；编码只能是字母。", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("保存") { invalid = !save(code, text) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { code = editing.code; text = editing.text }
    }
}
