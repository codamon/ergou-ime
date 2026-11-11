// ergou-ime — 联网记录: every network request ErgouIME makes, for the user to see.
// SPDX-License-Identifier: GPL-3.0-only
//
// Only two programs have network access (Shared/Privacy.swift): ErgouIME
// Settings (downloads, update checks) and ErgouIME Cloud (the opt-in cloud
// tidy-up). Each records every request it made, when it finishes, as one
// JSON line in the App Group container; Settings › 联网记录 shows them. The
// input method has no network access, so it never appears here.
//
// What is recorded: time, program, purpose, server, path, a description of
// what was sent in counts only ("识别文字 12 字、上文 0 字、我的词 3 个"),
// bytes sent and received, result. Never the text, context, terms, API key,
// headers or query strings.
//
// This is bookkeeping by the same programs that make the requests, not a
// tamper-proof audit; PRIVACY.md says how to check independently (nettop,
// Little Snitch, LuLu).

import Foundation

struct NetworkLogEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    /// "设置程序" or "云端整理进程".
    var program: String
    /// "检查更新", "下载拼音大词库", "云端整理", …
    var purpose: String
    var host: String
    var path: String
    /// What was sent, counts only.
    var sent: String
    var bytesSent: Int64
    var bytesReceived: Int64
    /// "HTTP 200", "网络错误", "已取消", …
    var result: String
}

enum NetworkLog {
    static let maxEntries = 1000

    static var file: URL {
        Paths.root.appendingPathComponent("NetworkLog", isDirectory: true)
            .appendingPathComponent("network-log.jsonl")
    }

    enum Program {
        static let settings = "设置程序"
        static let cloud = "云端整理进程"
    }

    /// Appends one entry. One write(2) with O_APPEND per entry, so the two
    /// programs never interleave half lines.
    static func record(_ entry: NetworkLogEntry) {
        guard var line = try? JSONEncoder().encode(entry) else { return }
        line.append(0x0A)
        let dir = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let fd = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    /// Convenience for a request described by its URL (host and path only).
    static func record(program: String, purpose: String, url: URL?, sent: String,
                       bytesSent: Int64, bytesReceived: Int64, result: String) {
        record(NetworkLogEntry(program: program, purpose: purpose,
                               host: url?.host ?? "?", path: url?.path ?? "",
                               sent: sent, bytesSent: bytesSent, bytesReceived: bytesReceived,
                               result: result))
    }

    /// Newest first. Lines that do not decode are skipped.
    static func load() -> [NetworkLogEntry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        let entries = data.split(separator: 0x0A).compactMap { try? decoder.decode(NetworkLogEntry.self, from: Data($0)) }
        return Array(entries.suffix(maxEntries).reversed())
    }

    /// Settings only: keep the newest `maxEntries` once the file is well over.
    static func trimIfNeeded() {
        guard let data = try? Data(contentsOf: file) else { return }
        let lines = data.split(separator: 0x0A)
        guard lines.count > maxEntries + maxEntries / 2 else { return }
        var kept = Data()
        for line in lines.suffix(maxEntries) { kept.append(line); kept.append(0x0A) }
        try? kept.write(to: file, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: file)
    }

    /// "HTTP 200" / error wording shared by the recorders.
    static func result(status: Int?, error: Error?) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .cancelled: return "已取消"
            case .timedOut: return "超时"
            default: return "网络错误"
            }
        }
        if error != nil { return "网络错误" }
        if let status { return "HTTP \(status)" }
        return "未完成"
    }
}
