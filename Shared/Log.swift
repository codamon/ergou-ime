// ergou-ime — logging (shared by the input method and Settings).
// SPDX-License-Identifier: GPL-3.0-only
//
// Privacy: log events and states only ("engine ready", "session created"),
// never user content. Do not interpolate key characters, preedit, candidates,
// commit text or transcripts into log messages. os.Logger keeps logs on this
// Mac; nothing is shipped anywhere.

import Foundation
import os

enum Log {
    /// Each process logs under its own bundle identifier.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.codamon.ergou"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let speech = Logger(subsystem: subsystem, category: "speech")
}
