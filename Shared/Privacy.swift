// ergou-ime — privacy rules.
// SPDX-License-Identifier: GPL-3.0-only
//
// ergou-ime ships as sandboxed programs, all inside ErgouIME.app:
//
//   ErgouIME.app           the input method (InputMethodKit). Typing, push-to-
//                          talk recording, on-device recognition, candidates.
//                          No network.
//   ErgouIME Settings.app  companion app (Contents/Library/LoginItems).
//                          Settings UI, model download, update checks.
//   ErgouIMECorrector.xpc  local correction models (Contents/XPCServices).
//                          No network.
//   ErgouIMECloud.xpc      the cloud tidy-up (Contents/XPCServices). Network
//                          (client only), used only when the user picks it;
//                          rule 11.
//
// Everything a user types or says is private. Reviewers should reject changes
// that break these rules.
//
//  1. The input method never touches the network.
//     Its entitlements do not include com.apple.security.network.client, so
//     the sandbox enforces this; anyone can check with
//     `codesign -d --entitlements - ErgouIME.app`. Its sources (ErgouIME/ and
//     Shared/) must not use networking APIs; scripts/check-no-network.sh
//     enforces that in CI. The same holds for ErgouIME Corrector. The cloud
//     tidy-up runs in its own service (rule 11); the input method only hands
//     it text over XPC and never sees the API key.
//
//  2. Settings goes online only for what the user asked for: downloading a
//     model or dictionary, 检查更新, and the automatic update check. The
//     automatic check is ON by default (D, 2026-11-10) and can be turned off
//     in Settings › 关于: at most once a day the input method (which has no
//     network) starts Settings in the background, which sends ONE request
//     for the latest release to api.github.com (no typed text, settings or
//     identifiers; only the app version in the User-Agent) and quits. A new
//     version is never downloaded or installed without the user's consent:
//     Settings asks first, then verifies the package (SHA-256, Developer ID
//     signature of the same team, Apple notarisation) and hands it to the
//     system Installer, which asks again. Nothing else runs in the
//     background or on a timer. (测试连接 for the cloud tidy-up goes through
//     ErgouIME Cloud, not Settings, and sends a fixed sentence.)
//
//  3. Models are downloaded by Settings only after a confirmation dialog that
//     shows the model name, size, source URL and licence, or from the
//     新手引导 download list, which shows the same plus the SHA-256 for each
//     item before the user presses 下载. The download is verified with
//     SHA-256. Every request is recorded in 联网记录 (NetworkLog.swift).
//     scripts/ are for development only.
//
//  4. No telemetry. No analytics SDKs, no counters sent anywhere. Logs
//     (Log.swift) never contain typed text, preedit, candidates, commit text
//     or transcripts, and stay on this Mac.
//
//  5. The clipboard is never read and there is no clipboard history. It is
//     written only on the user's own action, one item at a time:
//       - voice finished but there was no text field for the result (a
//         non-activating bubble then says "已复制");
//       - 复制, or 插入 with no text field, in the 常用语 / 语音记录 windows.
//
//  6. Secure input (password fields): no recording, no clipboard writes, no
//     candidates, no learning.
//
//  7. Audio stays in memory: captured, transcribed on-device, discarded.
//     Never written to disk, not even as a temporary file.
//
//  8. Learning stays local. librime's automatic frequency adjustment
//     (自动调频, enable_user_dict) is on by default.
//       - 五笔拼音混输 (ergou_wubi): no automatic phrase building (自动造词
//         off, D 2026-11-08); only the order of existing entries changes.
//       - 只用拼音 (ergou_pinyin_ime): the same switch also lets librime
//         remember committed sentences as new words, like any pinyin input
//         method (kept on purpose, D 2026-11-09). They go to that mode's own
//         user dictionary (ergou_pinyin_ime.userdb) and never appear in
//         五笔拼音混输.
//     Turning 调频 off stops both. The user can clear the user dictionaries.
//     The data lives in the input method's private container (Paths.swift)
//     and is never synced by us.
//
//  9. Nothing Settings writes can run inside the input method. Settings has
//     network access, so it never writes the Rime user directory (librime-lua
//     would execute scripts found there). It stores plain values in the
//     shared defaults; the input method validates them
//     (SettingsValidation.swift) and generates its Rime files itself, and
//     quarantines any rime.lua or lua/ that appears in its user directory.
//     Models in the App Group are checked against SHA-256 before loading.
//
// 10. 我的词 (voice terms, Shared/VoiceTerms.swift) stay on this Mac.
//     Manual terms are in the shared defaults; learned terms in the App
//     Group (Terms/learned-terms.json), written only by the input method.
//     Settings shows them and asks for 删除 / 固定 through the shared
//     defaults; it never writes the file and never uploads it. Both are
//     re-validated whenever they are read (no e-mail addresses, web
//     addresses, numbers or secret-looking strings; no prompt syntax). They
//     are hotwords for the on-device recogniser and — only with the cloud
//     tidy-up on — at most 50 of them go with each request (rule 11). Terms
//     the cloud model picks out are checked again (valid, present in the
//     corrected text) and stored locally like the rest. Nothing is learned
//     in secure input (rule 6). The file itself is never uploaded.
//
// 11. Cloud tidy-up (自动整理 › 云端模型, off by default). Only when the
//     user picks it, provides a key and dictates: while recording, each
//     time a segment (cut at a pause) has been recognised, ErgouIME Cloud
//     sends, for that segment (CloudStream):
//       - its recognised text (never audio);
//       - the name of the app being typed into;
//       - up to 50 of 我的词;
//       - as context, at most 200 characters in all: the end of this
//         dictation's earlier segments (already sent themselves), preceded
//         — if 「把光标前的文字一起发送」 is on (default on in this mode) —
//         by the text before the cursor, read once when recording starts.
//         The text before the cursor is never taken in secure input, where
//         nothing is recorded anyway (and sending stops if secure input
//         starts mid-recording), nor in terminals or password managers
//         (CloudTidy.noContextApps), where it is program output, not the
//         user's writing.
//     to the provider the user chose (Anthropic or an https:// address with
//     the same API, or an OpenAI-compatible https:// address), and nothing
//     else, nowhere else. So text leaves the Mac during dictation, not only
//     after it; Esc cancels the requests still running (CloudXPC.cancel)
//     but cannot unsend segments already sent. The service is
//     sandboxed with network.client and the App Group only
//     (scripts/check-no-network.sh). Its log has times, status codes and
//     character counts, never text. A segment whose request fails, or is
//     still out CloudTidy.finishWait (4 s) after the last one was
//     recognised, is typed as recognised.
//     The API key: written by Settings to the App Group container
//     (Cloud/api-key-<provider>, directory 0700, file 0600, excluded from
//     backups) and read only by ErgouIME Cloud (CloudShared/ is not compiled
//     into the input method). A file and not the Keychain because the
//     shared data-protection keychain needs a provisioning profile these
//     builds do not have (CloudShared/CloudKeyFile.swift). Any non-sandboxed
//     program running as this user could read the file (macOS 15+ asks the
//     user first when it is another developer's app). 删除 in Settings
//     removes it.

import Foundation

/// Compile-time statement of the policy, so code can refer to it (and tests
/// can assert it) instead of re-deciding it locally.
enum PrivacyPolicy {
    /// The input method process never makes network requests (rule 1).
    /// Settings is not covered by this flag; see `settingsNetworkOnUserActionOnly`.
    static let inputMethodNetworkAccess = false
    /// Settings may go online only for user actions and the once-a-day
    /// update check the user can turn off (rule 2).
    static let settingsNetworkOnUserActionOnly = true
    /// Automatic update checks default (rule 2): on, at most once a day;
    /// installing always needs the user's consent.
    static let automaticUpdateChecksDefault = true
    /// An update is downloaded and installed only after the user agrees (rule 2).
    static let updateInstallRequiresConsent = true
    /// Model downloads always go through a confirmation dialog (rule 3).
    static let modelDownloadRequiresConfirmation = true
    /// No telemetry of any kind (rule 4).
    static let telemetryEnabled = false
    /// The pasteboard is never read (rule 5).
    static let clipboardReadAllowed = false
    /// Pasteboard writes only on the user's action: voice or a pick-list item with no text field, or 复制 (rule 5).
    static let clipboardWriteOnlyForNoCursorVoice = true
    /// Nothing is recorded or written while secure input is on (rule 6).
    static let recordDuringSecureInput = false
    /// Recorded audio is never written to disk (rule 7).
    static let persistAudio = false
    /// 自动调频 default — librime enable_user_dict (rule 8). User can turn it
    /// off and clear the user dictionaries. Automatic phrase building is
    /// never enabled in 五笔拼音混输 (it breaks 四码唯一自动上屏); 只用拼音
    /// learns words into its own user dictionary.
    static let frequencyLearningDefault = true
    /// The 我的词 file is never uploaded; terms go only with cloud
    /// tidy-up requests the user turned on (rules 10, 11).
    static let voiceTermsUploaded = false
    /// The cloud tidy-up is off unless the user picks it (rule 11).
    static let cloudTidyDefault = false
    /// With the cloud tidy-up on, the text before the cursor is sent by
    /// default; the user can turn it off (rule 11).
    static let cloudSendContextDefault = true
}
