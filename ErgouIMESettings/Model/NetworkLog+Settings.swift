// ErgouIME Settings — record its own requests in 联网记录 (Shared/NetworkLog.swift).
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

extension NetworkLog {
    /// A finished (or failed, or cancelled) download task. Records the server
    /// that actually answered: GitHub release downloads are redirected from
    /// github.com to a download host, which is what a firewall shows.
    static func recordDownload(_ task: URLSessionTask, error: Error?, purpose: String) {
        let first = task.originalRequest?.url
        let last = task.currentRequest?.url ?? first
        let status = (task.response as? HTTPURLResponse)?.statusCode
        var sent = "下载请求（GET，没有正文）"
        if let a = first?.host, let b = last?.host, a != b { sent += "，由 \(a) 跳转" }
        record(program: Program.settings, purpose: purpose, url: last, sent: sent,
               bytesSent: task.countOfBytesSent, bytesReceived: task.countOfBytesReceived,
               result: result(status: status, error: error))
    }
}
