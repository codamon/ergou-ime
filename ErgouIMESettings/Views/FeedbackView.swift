// ErgouIME Settings — 反馈问题 sheet (关于 page).
// SPDX-License-Identifier: GPL-3.0-only
//
// Shows exactly what the report contains before anything leaves the
// window (FeedbackReport.swift says what is in it and what never is).

import AppKit
import SwiftUI

struct FeedbackView: View {
    let done: () -> Void
    @State private var environment = FeedbackReport.environment()
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("反馈问题").font(.headline)
            Text("二狗没有遥测，不知道你遇到了什么问题。下面是自动生成的环境信息：版本、系统和各项设置，不含你打过的字、说过的话、词库内容和麦克风名称。")
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(environment)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 380)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            Text("“在 GitHub 上提交”会在浏览器里打开一份填好这些信息的问题草稿，你补上问题描述再提交，那个页面是公开的。不用 GitHub 的话，点“复制”，再粘贴到邮件或聊天里发给开发者。本设置程序不会发送任何东西。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("取消", action: done).keyboardShortcut(.cancelAction)
                Spacer()
                Button(copied ? "已复制" : "复制") { copy() }
                Button("在 GitHub 上提交…") { openIssue() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("二狗输入法 · 环境信息\n" + environment, forType: .string)
        copied = true
    }

    private func openIssue() {
        guard let url = FeedbackReport.issueURL(environment: environment) else { return }
        NSWorkspace.shared.open(url)
        done()
    }
}
