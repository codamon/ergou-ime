// ErgouIME Settings — the "new version" window and the background check.
// SPDX-License-Identifier: GPL-3.0-only
//
// Two ways in:
//   - `--check-updates` (started by the input method, at most once a day):
//     BackgroundUpdateCheck runs instead of the settings UI. No window and
//     no Dock icon unless there is a newer version the user has not skipped;
//     then this window appears WITHOUT taking keyboard focus (the user may
//     be typing), with a Dock icon so it can be found again.
//   - 检查更新… in 关于: the same window, brought to the front.
// Nothing is downloaded until the user presses 下载并安装.

import AppKit
import SwiftUI

@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    static let shared = UpdateWindowController()
    private var window: NSWindow?
    private let installer = UpdateInstaller()
    /// Called when the window closes (background mode quits the app).
    var onClose: (() -> Void)?

    func show(_ update: AvailableUpdate, activate: Bool) {
        window?.close()
        let view = UpdateView(update: update, installer: installer) { [weak self] in self?.window?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "二狗输入法更新"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            // Visible, but keys keep going to the app the user is typing in.
            window.level = .floating
            window.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        if installer.isBusy { installer.cancel() }
        window = nil
        onClose?()
    }
}

private struct UpdateView: View {
    let update: AvailableUpdate
    @ObservedObject var installer: UpdateInstaller
    let close: () -> Void

    private var current: String { AppVersion.current?.description ?? "?" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("二狗输入法 \(update.version.description) 可以更新了").font(.title2).bold()
            Text("你现在用的是 \(current)。更新会下载 \(ByteCountFormatter.string(fromByteCount: update.packageSize, countStyle: .file)) 的安装包，核对签名和苹果公证后打开系统安装器，在安装器里确认才会安装。设置、词库、调频记录和语音模型都会保留。")
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(height: 220)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            Link("在 GitHub 上查看", destination: update.pageURL).font(.callout)
            status
            HStack {
                if case .idle = installer.phase {
                    Button("跳过这个版本") {
                        Paths.sharedDefaults.set(update.version.description, forKey: SettingKey.skippedUpdateVersion)
                        close()
                    }
                }
                Spacer()
                switch installer.phase {
                case .downloading, .verifying:
                    Button("取消", role: .cancel) { installer.cancel() }
                        .disabled(installer.phase == .verifying)
                case .opened:
                    Button("完成") { close() }.keyboardShortcut(.defaultAction)
                case .failed:
                    Button("关闭") { close() }
                    Button("重试") { installer.start(update) }.keyboardShortcut(.defaultAction)
                case .idle:
                    Button("以后再说", role: .cancel) { close() }.keyboardShortcut(.cancelAction)
                    Button("下载并安装") { installer.start(update) }.keyboardShortcut(.defaultAction)
                }
            }
            Text("每天最多检查一次，可以在 设置 › 关于 里关掉。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 520)
    }

    private var notes: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: update.notes, options: options)) ?? AttributedString(update.notes)
    }

    @ViewBuilder private var status: some View {
        switch installer.phase {
        case let .downloading(received, total):
            ProgressView(value: Double(received), total: Double(max(total, 1))) {
                Text("正在下载 \(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                    .font(.caption).monospacedDigit()
            }
        case .verifying:
            ProgressView { Text("正在核对校验值、签名和苹果公证…").font(.caption) }
        case .opened:
            Label("已打开安装器，按提示完成安装。安装时输入法会自动重启。", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }
}

/// `--check-updates`: the whole app run when the input method starts the
/// daily check. Plain AppKit, no settings window.
enum BackgroundUpdateCheck {
    static let argument = "--check-updates"

    static var isRequested: Bool { CommandLine.arguments.contains(argument) }

    @MainActor
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)        // no Dock icon while checking
        let delegate = Delegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor
    private final class Delegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            guard SharedSettings.automaticUpdateChecks else { NSApp.terminate(nil); return }
            UpdateInstaller.removeOldPackages()
            Task { @MainActor in
                let result = await UpdateChecker.check()
                guard case let .available(update) = result,
                      Paths.sharedDefaults.string(forKey: SettingKey.skippedUpdateVersion) != update.version.description
                else { NSApp.terminate(nil); return }
                NSApp.setActivationPolicy(.regular)    // findable in the Dock while the window is up
                UpdateWindowController.shared.onClose = { NSApp.terminate(nil) }
                UpdateWindowController.shared.show(update, activate: false)
            }
        }
    }
}
