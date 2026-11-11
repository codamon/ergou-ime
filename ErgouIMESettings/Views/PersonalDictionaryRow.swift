// ErgouIME Settings — 个人词库 row: import, count, clear (used in 输入 and the welcome guide).
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

struct PersonalDictionaryRow: View {
    @State private var count = ImportedWords.load().count
    @State private var result: String?
    @State private var confirmClear = false

    var body: some View {
        LabeledContent {
            HStack {
                if count > 0 {
                    Button("清空…", role: .destructive) { confirmClear = true }
                }
                Button("导入…") { pickFile() }
            }
        } label: {
            Text("个人词库")
            Text("把原来输入法里攒下的词搬过来：搜狗、QQ、百度、Rime 导出的 .txt 词库，或者每行一个词的文本；macOS“文本替换”导出的 .plist 会加进常用语。文件只在这台 Mac 上读取。")
            HStack(spacing: 4) {
                Image(systemName: count > 0 ? "checkmark.circle.fill" : "tray")
                    .foregroundStyle(count > 0 ? Color.green : Color.secondary)
                Text(count > 0 ? "已导入 \(count) 个词" : "还没有导入")
            }
        }
        .alert("导入个人词库", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("好") { result = nil }
        } message: {
            Text(result ?? "")
        }
        .confirmationDialog("清空个人词库？", isPresented: $confirmClear) {
            Button("清空", role: .destructive) {
                ImportedWords.clear()
                SharedNotifications.post(SharedNotifications.redeployRime)
                count = 0
            }
        } message: {
            Text("导入的 \(count) 个词都会删除。已经加进常用语的不受影响。")
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "选择要导入的词库文件"
        panel.message = "支持 .txt 词库（搜狗、QQ、百度、Rime 导出，或每行一个词）和 macOS 文本替换的 .plist"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch PersonalDictionaryImport.read(url) {
        case let .success(parsed):
            do {
                let summary = try parsed.apply()
                count = summary.wordsTotal
                result = summary.message + (summary.wordsAdded > 0 ? "输入法正在重新部署，稍等片刻就能打出来。" : "")
            } catch {
                result = "保存失败：没法写入个人词库。"
            }
        case let .failure(failure):
            result = failure.message
        }
    }
}
