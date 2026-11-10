// ergou-ime — the cloud tidy-up API key.
// SPDX-License-Identifier: GPL-3.0-only
//
// Compiled into ErgouIME Settings (writes it) and ErgouIME Cloud (reads it)
// only — never into the input method (project.yml; scripts/check-no-network.sh
// fails if ErgouIME/ refers to it).
//
// Why a file and not the Keychain (tested on D's Mac, macOS 27, 2026-11-10,
// two sandboxed test apps with the same team and App Group):
//   - the data-protection keychain with the App Group as access group
//     returns errSecMissingEntitlement (-34018): it needs an
//     application-identifier from a provisioning profile, which these
//     Developer ID / Apple Development builds do not have;
//   - adding keychain-access-groups without a profile gets the program
//     killed at launch;
//   - the login (file-based) keychain ties an item to the program that
//     created it; another program gets a password prompt unless the item's
//     ACL names it (deprecated SecAccess API; not tried).
// So the key lives in the App Group container, readable by nothing but this
// user's processes:
//   ~/Library/Group Containers/<TEAMID>.com.codamon.ergou/Cloud/api-key-<provider>
//   directory 0700, file 0600, excluded from backups. One file per provider.
// Other sandboxed apps cannot read it; since macOS 15 a non-sandboxed app of
// another developer reading a group container triggers a system prompt.
// See Shared/Privacy.swift rule 11.

import Foundation

enum CloudKeyFile {
    static var directory: URL? {
        Paths.sharedContainer?.appendingPathComponent("Cloud", isDirectory: true)
    }

    static func url(_ provider: CloudProvider) -> URL? {
        directory?.appendingPathComponent("api-key-" + provider.rawValue)
    }

    /// Printable ASCII without spaces, 8–512 characters.
    static func valid(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...512).contains(key.count),
              key.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) else { return nil }
        return key
    }

    static func load(_ provider: CloudProvider) -> String? {
        guard let file = url(provider), let data = try? Data(contentsOf: file), data.count <= 1024 else { return nil }
        return valid(String(decoding: data, as: UTF8.self))
    }

    static func isPresent(_ provider: CloudProvider) -> Bool { load(provider) != nil }

    /// Writes a temporary 0600 file next to the key and renames it, so the
    /// key is never readable with wider permissions.
    @discardableResult
    static func save(_ raw: String, for provider: CloudProvider) -> Bool {
        guard let key = valid(raw), let dir = directory, let file = url(provider) else { return false }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString)")
            guard fm.createFile(atPath: tmp.path, contents: Data(key.utf8),
                                attributes: [.posixPermissions: 0o600]) else { return false }
            if fm.fileExists(atPath: file.path) {
                _ = try fm.replaceItemAt(file, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: file)
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var u = file
            try? u.setResourceValues(values)
            return load(provider) == key
        } catch {
            return false
        }
    }

    static func delete(_ provider: CloudProvider) {
        guard let file = url(provider) else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
