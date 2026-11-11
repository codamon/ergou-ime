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

    /// Appends one entry and keeps the file bounded. Settings and ErgouIME
    /// Cloud both write: every change happens under an exclusive flock on
    /// the same file, appends are one write(2) with O_APPEND, and trimming
    /// rewrites the file in place (never by renaming a new file over it),
    /// so no entry written by the other program during a trim is lost and
    /// nobody keeps writing into an unlinked file (audit 0.4.1 M7). The cap
    /// holds even if the 联网记录 page is never opened.
    static func record(_ entry: NetworkLogEntry) {
        guard var line = try? JSONEncoder().encode(entry) else { return }
        line.append(0x0A)
        withLockedFile(create: true) { fd in
            _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            trimLocked(fd)
        }
    }

    /// Trim once the file holds more than this many entries…
    private static var trimAbove: Int { maxEntries + maxEntries / 2 }
    /// …which is only counted once it is at least this big (an entry is
    /// 300–500 bytes), so most appends do not read the file.
    private static let trimCheckBytes = 256 << 10
    /// Never read more than the tail of a file someone made huge.
    private static let maxReadBytes = 4 << 20

    private static func withLockedFile(create: Bool, _ body: (Int32) -> Void) {
        if create {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
        let fd = open(file.path, O_RDWR | O_APPEND | O_NOFOLLOW | (create ? O_CREAT : 0), 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, flock(fd, LOCK_EX) == 0 else { return }
        defer { flock(fd, LOCK_UN) }
        body(fd)
    }

    /// The last `maxReadBytes` of the file, whole lines only.
    private static func tailLines(_ fd: Int32) -> (lines: [Data], truncated: Bool) {
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_size > 0 else { return ([], false) }
        let size = Int(st.st_size), from = max(0, size - maxReadBytes)
        var data = Data(count: size - from)
        let n = data.withUnsafeMutableBytes { pread(fd, $0.baseAddress, $0.count, off_t(from)) }
        guard n > 0 else { return ([], false) }
        var lines = data.prefix(n).split(separator: 0x0A).map { Data($0) }
        if from > 0, !lines.isEmpty { lines.removeFirst() }       // probably cut in half
        return (lines, from > 0)
    }

    /// Caller holds the lock.
    private static func trimLocked(_ fd: Int32) {
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_size >= off_t(trimCheckBytes) else { return }
        let (lines, truncated) = tailLines(fd)
        guard truncated || lines.count > trimAbove else { return }
        var kept = Data()
        for line in lines.suffix(maxEntries) { kept.append(line); kept.append(0x0A) }
        guard ftruncate(fd, 0) == 0 else { return }
        _ = kept.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }      // O_APPEND: at the (new) end
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
        var lines: [Data] = []
        withLockedFile(create: false) { fd in lines = tailLines(fd).lines }
        let decoder = JSONDecoder()
        let entries = lines.suffix(maxEntries * 2).compactMap { try? decoder.decode(NetworkLogEntry.self, from: $0) }
        return Array(entries.suffix(maxEntries).reversed())
    }

    /// Also done on every append; Settings calls it when the page opens.
    static func trimIfNeeded() {
        withLockedFile(create: false) { fd in trimLocked(fd) }
    }

    /// Empties the file in place (the other program may have it open).
    static func clear() {
        withLockedFile(create: false) { fd in _ = ftruncate(fd, 0) }
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
