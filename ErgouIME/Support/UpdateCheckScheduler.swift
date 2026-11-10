// ergou-ime — start the once-a-day update check (Shared/Privacy.swift rule 2).
// SPDX-License-Identifier: GPL-3.0-only
//
// The input method has no network access and never gets one. When it is
// activated and 自动检查更新 is on, it starts ErgouIME Settings in the
// background at most once every 24 hours (SettingsLaunchRequest.checkUpdates;
// launch arguments are dropped for sandboxed callers). Settings
// (which has network.client) asks GitHub for the latest release, shows a
// window only when there is a newer version, and quits otherwise. Nothing
// is passed to Settings except that one request.

import AppKit

enum UpdateCheckScheduler {
    static let interval: TimeInterval = 24 * 60 * 60
    /// This process's own defaults (not the shared ones): when it last
    /// started a check, so a check that fails before it reaches GitHub
    /// (no network, Settings crashed) is not retried on every keystroke.
    private static let lastLaunchKey = "lastUpdateCheckLaunch"

    static func maybeStart() {
        guard SharedSettings.automaticUpdateChecks else { return }
        let now = Date()
        if let last = SharedSettings.lastUpdateCheck, now.timeIntervalSince(last) < interval { return }
        if let launched = UserDefaults.standard.object(forKey: lastLaunchKey) as? Date,
           now.timeIntervalSince(launched) < interval { return }
        // Settings already open: it would only be brought forward and never
        // read the request. Try again another time.
        let settingsID = Bundle(url: SettingsLauncher.settingsAppURL)?.bundleIdentifier
        if let settingsID, !NSRunningApplication.runningApplications(withBundleIdentifier: settingsID).isEmpty { return }

        UserDefaults.standard.set(now, forKey: lastLaunchKey)
        SettingsLaunchRequest.checkUpdates.post()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: SettingsLauncher.settingsAppURL, configuration: configuration) { _, error in
            if error != nil { Log.app.error("Could not start the update check") }
        }
    }
}
