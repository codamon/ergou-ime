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
        record(program: Program.settings, purpose: purpose, url: last, sent: downloadSent(first: first, last: last),
               bytesSent: task.countOfBytesSent, bytesReceived: task.countOfBytesReceived,
               result: result(status: status, error: error))
    }

    /// "下载请求…", noting a redirect to another server.
    static func downloadSent(first: URL?, last: URL?) -> String {
        var sent = "下载请求（GET，没有正文）"
        if let a = first?.host, let b = last?.host, a != b { sent += "，由 \(a) 跳转" }
        return sent
    }

    /// Written when a download starts. Entries are otherwise written when a
    /// request ends, so one cut short by quitting Settings (closing the
    /// window, an update's preinstall) would never be listed (audit 0.4.1
    /// M7). A finished download has two lines: 开始 and its result.
    static func recordStart(purpose: String, url: URL) {
        record(program: Program.settings, purpose: purpose, url: url,
               sent: "下载请求（GET，没有正文）", bytesSent: 0, bytesReceived: 0, result: "开始")
    }
}
