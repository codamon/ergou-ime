// ergou-ime — click-to-insert list windows: 语音记录… and 常用语….
// SPDX-License-Identifier: GPL-3.0-only
//
// Both live in the input method process: voice history never leaves its
// sandbox container (VoiceHistory.swift). Click an entry: the window closes,
// focus returns to the app you were typing in, and the text is inserted at
// the caret. The copy button puts it on the clipboard instead (your choice).

import AppKit
import SwiftUI

struct PickItem: Identifiable {
    let id: String
    let text: String
    /// Shown small under the text: a date, a code, …
    let detail: String
}

final class PickListWindow: NSObject, NSWindowDelegate {
    static let voiceHistory = PickListWindow(title: "语音记录",
        empty: "还没有语音记录",
        hint: "点一下右 Option 说话，结果会记在这里。只存在这台 Mac 上，像密码、验证码的内容不记。",
        symbol: "waveform")
    static let phrases = PickListWindow(title: "常用语",
        empty: "还没有常用语",
        hint: "在设置 › 常用语 里添加经常要打的话。",
        symbol: "text.quote")

    private let title: String, empty: String, hint: String, symbol: String
    private var window: NSWindow?

    private init(title: String, empty: String, hint: String, symbol: String) {
        self.title = title; self.empty = empty; self.hint = hint; self.symbol = symbol
    }

    func show(_ items: [PickItem]) {
        let view = PickListView(items: items, empty: empty, hint: hint, symbol: symbol,
                                insert: { [weak self] text in self?.insert(text) },
                                copy: { [weak self] text in self?.copy(text) })
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = title
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        window?.contentView = NSHostingView(rootView: view)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func insert(_ text: String) {
        window?.orderOut(nil)
        NSApp.hide(nil)
        // Give the previous app back its focus, then type into it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if let target = VoiceSession.shared.target, target.insertVoiceText(text) { return }
            guard !SecureInput.isActive else { return }      // Privacy rule 6
            self.copy(text)
            VoiceHUD.shared.note("没有输入框，已复制到剪贴板", symbol: "doc.on.clipboard", for: 2)
        }
    }

    /// Only on the user's own click (复制, or 插入 with no text field) —
    /// Privacy rule 5. Never in a password field (rule 6).
    private func copy(_ text: String) {
        guard !SecureInput.isActive else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func windowWillClose(_ notification: Notification) { NSApp.hide(nil) }
}

private struct PickListView: View {
    let items: [PickItem]
    let empty: String, hint: String, symbol: String
    let insert: (String) -> Void
    let copy: (String) -> Void
    @State private var hovered: String?
    @State private var copied: String?

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text(empty).font(.headline)
                    Text(hint).font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(items) { row($0) }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(.top, 24)
        .frame(minWidth: 380, minHeight: 300)
    }

    private func row(_ item: PickItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .font(.system(size: 14))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !item.detail.isEmpty {
                    Text(item.detail).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Button {
                copy(item.text)
                copied = item.id
            } label: {
                Image(systemName: copied == item.id ? "checkmark" : "doc.on.doc").frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(hovered == item.id || copied == item.id ? 1 : 0)
            .help("复制")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Surface.radiusMedium - 2, style: .continuous)
            .fill(hovered == item.id ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
        .onTapGesture { insert(item.text) }
        .help("点一下插入到光标处")
    }
}
