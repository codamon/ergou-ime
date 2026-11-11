// ErgouIME Corrector — XPC service entry point.
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: CorrectorXPC.self)
        connection.exportedObject = Corrector.shared
// A local model deleted in Settings: drop our private clone (it would be the
// only copy left, up to 4.7 GB).
SpeechModelFiles.removeOrphanedPrivateCopies()
        connection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
