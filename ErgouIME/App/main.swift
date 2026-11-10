// ergou-ime — entry point.
// SPDX-License-Identifier: GPL-3.0-only
//
// Starts the InputMethodKit server. The structure follows the usual IMK
// pattern (as also used by Squirrel / 鼠鬚管, GPL-3.0), written from scratch.
//
// Command-line helpers (used by scripts/install.sh):
//   ErgouIME --register-input-source   register this bundle with Text Input Sources
//   ErgouIME --enable-input-source     enable and select the Wubi input mode
//   ErgouIME --enable-input-source-only   enable without selecting (pkg postinstall)

import AppKit
import InputMethodKit

let arguments = CommandLine.arguments

if arguments.contains("--register-input-source") {
    exit(InputSourceRegistrar.register(bundleURL: Bundle.main.bundleURL) ? 0 : 1)
}
if arguments.contains("--enable-input-source-only") {
    exit(InputSourceRegistrar.enable(select: false) ? 0 : 1)
}
if arguments.contains("--enable-input-source") {
    exit(InputSourceRegistrar.enableAndSelect() ? 0 : 1)
}

let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
    ?? "com.codamon.inputmethod.Ergou_Connection"

guard let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier) else {
    Log.app.fault("Could not start IMKServer")
    exit(1)
}

// Engine setup (librime deploy, etc.) happens once per process.
EngineHost.shared.start()
// Right Option under any input source, once Input Monitoring is allowed.
GlobalHotkey.shared.start()
// Settings' 测试连接 for the cloud tidy-up (ErgouIME Cloud does the request).
CloudCorrector.shared.start()
Log.app.info("ErgouIME started")

withExtendedLifetime(server) {
    NSApplication.shared.run()
}
