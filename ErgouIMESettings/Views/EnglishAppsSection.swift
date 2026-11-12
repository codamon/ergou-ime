// ErgouIME Settings — 输入 › 默认用英文的应用.
// SPDX-License-Identifier: GPL-3.0-only
//
// Apps whose text fields start in English (terminals and code editors by
// default). Only bundle identifiers are stored, in the shared settings; the
// input method checks them again (Shared/KeyOptions.swift, EnglishApps) and
// needs no redeploy: it reads the list when a text field becomes active.
// Names and icons are looked up here, for display, and stored nowhere.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EnglishAppsSection: View {
    @State private var apps = SharedSettings.englishApps

    var body: some View {
        Section {
            if apps.isEmpty {
                Text("没有应用。所有应用都从中文开始。").foregroundStyle(.secondary)
            }
            // One row per app that is on this Mac; the rest (most of the
            // default terminals and editors, usually) share one line.
            let installed = apps.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
            let missing = apps.filter { !installed.contains($0) }
            ForEach(installed, id: \.self) { id in
                EnglishAppRow(bundleID: id) { save(apps.filter { $0 != id }) }
            }
            if !missing.isEmpty {
                LabeledContent {
                    Button("移除") { save(installed) }
                } label: {
                    Text("没装在这台 Mac 上的 \(missing.count) 个")
                    Text(missing.map { EnglishApps.names[$0] ?? $0 }.joined(separator: "、"))
                }
            }
            HStack {
                Button("添加应用…") { add() }
                Spacer()
                if apps != EnglishApps.defaults {
                    Button("恢复默认") { save(EnglishApps.defaults) }
                }
            }
        } header: {
            Text("默认用英文的应用")
        } footer: {
            Text("在这些应用里，二狗从英文开始，按 Shift 换成中文。其他应用从中文开始。每个应用会记住你上次切到的是中文还是英文；把应用加进来或移出去，它就重新按这里的来。")
        }
    }

    private func save(_ ids: [String]) {
        SharedSettings.saveEnglishApps(ids)
        apps = SharedSettings.englishApps
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "添加"
        panel.message = "选择打开时默认用英文的应用"
        guard panel.runModal() == .OK else { return }
        let chosen = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter(EnglishApps.isValid)
        save(apps + chosen.filter { !apps.contains($0) })
    }
}

private struct EnglishAppRow: View {
    let bundleID: String
    let remove: () -> Void

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        LabeledContent {
            Button("移除", action: remove)
        } label: {
            HStack(spacing: 8) {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable().frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
            }
        }
    }
}
