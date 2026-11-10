// ergou-ime — open the nested ErgouIME Settings app.
// SPDX-License-Identifier: GPL-3.0-only

import AppKit

enum SettingsLauncher {
    enum Page: String {
        case general, models, about
    }

    /// ErgouIME.app/Contents/Library/LoginItems/ErgouIME Settings.app
    static var settingsAppURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems", isDirectory: true)
            .appendingPathComponent("ErgouIME Settings.app", isDirectory: true)
    }

    static func open(page: Page = .general) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = ["--page", page.rawValue]
        NSWorkspace.shared.openApplication(at: settingsAppURL, configuration: configuration) { _, error in
            if error != nil {
                Log.app.error("Could not open ErgouIME Settings")
            }
        }
    }
}
