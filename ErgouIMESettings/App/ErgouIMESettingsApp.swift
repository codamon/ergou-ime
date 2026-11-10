// ErgouIME Settings — companion app (SwiftUI, macOS 13).
// SPDX-License-Identifier: GPL-3.0-only
//
// Nested inside ErgouIME.app (Contents/Library/LoginItems/). Opened from the
// input method's menu ("打开设置…", "关于") with `--page <general|models|about>`,
// or by the input method with `--check-updates` once a day (main.swift).
//
// This is the only ergou-ime program allowed to go online, and only when the
// user explicitly asks (Shared/Privacy.swift rule 2). M0 contains no network
// code at all: the model download is a UI placeholder.

import SwiftUI

/// Started from main.swift (not @main): `--check-updates` runs
/// BackgroundUpdateCheck instead of this UI.
struct ErgouIMESettingsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = PageRouter(initial: PageRouter.initialPage())

    var body: some Scene {
        WindowGroup("二狗输入法设置") {
            SettingsRootView()
                .environmentObject(router)
                .frame(minWidth: 620, idealWidth: 640, minHeight: 520, idealHeight: 640)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Closing the settings window quits the app, so its Dock icon goes away
/// (D, 2026-11-10: the icon stayed after the window was closed). SwiftUI's
/// WindowGroup keeps the process alive by default. The input method opens a
/// fresh instance from its menu every time (SettingsLauncher), so nothing
/// needs the process afterwards; a running download belongs to the window
/// and is cancelled with it, as before.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, phrases, models, terms, about
    // Raw values stay ("general", "models") so `--page` from the input
    // method's menu keeps working.
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "输入"
        case .phrases: return "常用语"
        case .models: return "语音"
        case .terms: return "我的词"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "keyboard"
        case .phrases: return "text.quote"
        case .models: return "waveform"
        case .terms: return "character.book.closed"
        case .about: return "info.circle"
        }
    }
}

final class PageRouter: ObservableObject {
    @Published var page: SettingsPage

    init(initial: SettingsPage) { page = initial }

    /// From the input method's request (main.swift), else `--page`.
    static func initialPage() -> SettingsPage {
        switch launchRequest {
        case .pageModels: return .models
        case .pageAbout: return .about
        case .pageGeneral: return .general
        case .checkUpdates, nil: break
        }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--page"), i + 1 < args.count,
           let page = SettingsPage(rawValue: args[i + 1]) {
            return page
        }
        return .general
    }
}
