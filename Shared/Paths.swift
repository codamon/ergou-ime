// ergou-ime — on-disk locations (shared by the input method and Settings).
// SPDX-License-Identifier: GPL-3.0-only
//
// Both programs are sandboxed, so FileManager's "Application Support" is
// redirected into each app's own container
// (~/Library/Containers/<bundle-id>/Data/Library/Application Support).
//
// App Group container — only what both programs need, nothing executable:
//
//   ~/Library/Group Containers/<TEAMID>.com.codamon.ergou/
//     Models/sense-voice/    model.int8.onnx, tokens.txt (written by Settings;
//                            the input method checks SHA-256 before loading)
//   + UserDefaults(suiteName: appGroupID): settings values and manual
//     phrases written by Settings. The input method treats them as untrusted
//     input (SettingsValidation.swift).
//
// Rime user data stays in the INPUT METHOD's private container, not in the
// group: librime-lua searches <user dir>/lua/ before the bundled scripts and
// runs <user dir>/rime.lua if present. If Settings (which has network access)
// could write that directory, it could inject code into the process that sees
// every key and can record audio. So Settings never writes Rime files; the
// input method generates *.custom.yaml and wubi86_jidian_user.dict.yaml from
// validated settings (ErgouIME/Engine/RimeUserConfig.swift).

import Foundation

enum Paths {
    /// "<TEAMID>.com.codamon.ergou", injected into both Info.plists from
    /// the ERGOU_APP_GROUP_ID build setting (Config/Common.xcconfig).
    static let appGroupID: String =
        Bundle.main.object(forInfoDictionaryKey: "ErgouAppGroupID") as? String ?? ""

    /// The App Group container. nil means the app was signed without the
    /// application-groups entitlement (e.g. no team ID configured).
    static var sharedContainer: URL? {
        guard !appGroupID.isEmpty, !appGroupID.hasPrefix(".") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Fallback when the group container is unavailable: this app's own
    /// (sandbox-redirected) Application Support. Not shared — logs an error.
    private static var privateFallback: URL {
        Log.app.error("App Group container unavailable; falling back to private container")
        return privateRoot
    }

    static var root: URL { sharedContainer ?? privateFallback }

    /// This process's own (sandbox-redirected) Application Support.
    static var privateRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ErgouIME", isDirectory: true)
    }

    /// librime user data (custom yaml, userdb, build cache). Input method
    /// only — see the comment at the top of this file.
    static var rimeUserData: URL { privateRoot.appendingPathComponent("Rime", isDirectory: true) }

    /// Speech models, downloaded by Settings (never bundled, never in git).
    static var models: URL { root.appendingPathComponent("Models", isDirectory: true) }

    /// Shared settings between the two programs.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID.isEmpty ? nil : appGroupID) ?? .standard
    }

    /// Read-only Rime data shipped inside ErgouIME.app (scripts/embed-vendor.sh).
    static var rimeSharedData: URL? {
        Bundle.main.sharedSupportURL?.appendingPathComponent("rime-data", isDirectory: true)
    }
}
