// ErgouIME Settings — the cloud tidy-up API key (CloudShared/CloudKeyFile.swift).
// SPDX-License-Identifier: GPL-3.0-only
//
// Stage A kept the key in Settings' own login-keychain item, which ErgouIME
// Cloud cannot read. Move such a key to the key file once, then delete the
// keychain item.

import Foundation
import Security

enum CloudKey {
    private static let legacyQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.codamon.ergou.cloud-correction",
        kSecAttrAccount as String: "anthropic",
    ]

    static func migrateLegacyKeychainItem() {
        var query = legacyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return }
        if !CloudKeyFile.isPresent(.anthropic) {
            CloudKeyFile.save(String(decoding: data, as: UTF8.self), for: .anthropic)
        }
        if CloudKeyFile.isPresent(.anthropic) { SecItemDelete(legacyQuery as CFDictionary) }
    }
}
