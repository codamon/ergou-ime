// ErgouIME Settings — entry point.
// SPDX-License-Identifier: GPL-3.0-only
//
// The input method's once-a-day update check (SettingsLaunchRequest
// .checkUpdates, or `--check-updates` when started by hand; Shared/
// Privacy.swift rule 2): check, show a window only if there is a new
// version, quit. Anything else: the settings window, on the requested page.

import AppKit

let launchRequest = SettingsLaunchRequest.take()

if BackgroundUpdateCheck.isRequested || launchRequest == .checkUpdates {
    MainActor.assumeIsolated { BackgroundUpdateCheck.run() }
} else {
    ErgouIMESettingsApp.main()
}
