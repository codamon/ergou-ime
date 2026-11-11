// ergou-ime — open the 新手引导 the first time the input method is used.
// SPDX-License-Identifier: GPL-3.0-only
//
// Until Settings has shown the guide (SettingKey.welcomeShown, written by
// Settings), the first activation in each run of the input method starts
// Settings with SettingsLaunchRequest.welcome, without taking focus from the
// app being typed in. Settings shows the guide in its window.

import AppKit

enum WelcomeLauncher {
    private static var triedThisRun = false

    /// True if it started Settings (the caller then skips other launches).
    @discardableResult
    static func maybeShow() -> Bool {
        guard !triedThisRun, !(Paths.sharedDefaults.object(forKey: SettingKey.welcomeShown) as? Bool ?? false) else { return false }
        triedThisRun = true
        let settingsID = Bundle(url: SettingsLauncher.settingsAppURL)?.bundleIdentifier
        if let settingsID, !NSRunningApplication.runningApplications(withBundleIdentifier: settingsID).isEmpty { return false }
        SettingsLaunchRequest.welcome.post()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: SettingsLauncher.settingsAppURL, configuration: configuration) { _, error in
            if error != nil { Log.app.error("Could not open the welcome guide") }
        }
        return true
    }
}
