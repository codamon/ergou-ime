// ErgouIME Settings — download, verify and open an update (after the user agreed).
// SPDX-License-Identifier: GPL-3.0-only
//
// Runs only after the user pressed 下载并安装 (Shared/Privacy.swift rule 2):
//   1. download ErgouIME-<version>.pkg and its .sha256 from the release
//      (ephemeral session; progress; cancellable)
//   2. the package must match the .sha256 (a complete, unchanged download)
//   3. `pkgutil --check-signature` must report a Developer ID Installer
//      certificate of OUR team (the team ID in our own App Group ID) and
//      Apple notarisation — a package from anyone else is refused even if
//      the release page was tampered with
//   4. open it in the system Installer, which shows its own pages and asks
//      the user to install. Its preinstall script quits the input method and
//      this app; the new input method starts on the next keystroke.
// The package stays in this app's own container (Updates/) until the next
// update check removes it.

import AppKit
import Foundation

@MainActor
final class UpdateInstaller: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(received: Int64, total: Int64)
        case verifying
        case opened
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private var session: URLSession?
    private var update: AvailableUpdate?

    var isBusy: Bool {
        switch phase {
        case .downloading, .verifying: return true
        default: return false
        }
    }

    nonisolated static var folder: URL { Paths.privateRoot.appendingPathComponent("Updates", isDirectory: true) }

    /// Old downloaded packages (the update check calls this).
    nonisolated static func removeOldPackages() {
        try? FileManager.default.removeItem(at: folder)
    }

    func start(_ update: AvailableUpdate) {
        guard !isBusy else { return }
        self.update = update
        phase = .downloading(received: 0, total: update.packageSize)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: Delegate(owner: self, purpose: "下载更新 \(update.version)"), delegateQueue: nil)
        self.session = session
        session.downloadTask(with: update.packageURL).resume()
    }

    func cancel() {
        session?.invalidateAndCancel()
        session = nil
        phase = .idle
    }

    fileprivate func progress(_ received: Int64, _ total: Int64) {
        guard case .downloading = phase else { return }
        phase = .downloading(received: received, total: total > 0 ? total : (update?.packageSize ?? 0))
    }

    fileprivate func finished(_ file: URL?, error: String?) {
        session?.finishTasksAndInvalidate()
        session = nil
        guard let update, let file else {
            if phase != .idle { phase = .failed(error ?? "下载失败。") }
            return
        }
        phase = .verifying
        Task.detached(priority: .userInitiated) {
            let result = await Self.verify(file, update: update)
            await MainActor.run {
                switch result {
                case let .success(pkg):
                    if NSWorkspace.shared.open(pkg) {
                        self.phase = .opened
                    } else {
                        self.phase = .failed("打不开安装器。安装包在：\(pkg.path)")
                    }
                case let .failure(message):
                    try? FileManager.default.removeItem(at: file)
                    self.phase = .failed(message.text)
                }
            }
        }
    }

    struct Message: Error { let text: String }

    /// Moves the checked package to Updates/ErgouIME-<version>.pkg.
    nonisolated private static func verify(_ file: URL, update: AvailableUpdate) async -> Swift.Result<URL, Message> {
        // 2. SHA-256 from the release's .sha256 ("<hex>  ErgouIME-x.pkg").
        let checksum = try? await URLSession(configuration: .ephemeral).data(from: update.checksumURL)
        NetworkLog.record(program: NetworkLog.Program.settings, purpose: "下载更新校验值 \(update.version)",
                          url: checksum?.1.url ?? update.checksumURL, sent: "下载请求（GET，没有正文）",
                          bytesSent: 0, bytesReceived: Int64(checksum?.0.count ?? 0),
                          result: NetworkLog.result(status: (checksum?.1 as? HTTPURLResponse)?.statusCode,
                                                    error: checksum == nil ? URLError(.unknown) : nil))
        guard let (data, response) = checksum,
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8),
              let expected = text.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased(),
              expected.count == 64, expected.allSatisfy(\.isHexDigit) else {
            return .failure(Message(text: "下载校验文件失败。"))
        }
        guard FileHash.sha256(of: file) == expected else {
            return .failure(Message(text: "下载的安装包校验不通过（SHA-256 不符），已丢弃。"))
        }
        // 3. Signed by our team and notarised.
        guard let team = ourTeamID else { return .failure(Message(text: "读不到本程序的开发者团队 ID，没法核对安装包签名。")) }
        guard let report = pkgutilCheckSignature(file) else {
            return .failure(Message(text: "没法检查安装包的签名。"))
        }
        let lines = report.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let signedForDistribution = lines.contains { $0.hasPrefix("Status: signed by a developer certificate issued by Apple for distribution") }
        let notarized = lines.contains { $0.hasPrefix("Notarization: trusted by the Apple notary service") }
        // The leaf certificate is the first line of the chain: "1. Developer ID Installer: Name (TEAMID)".
        let leaf = lines.first { $0.hasPrefix("1. ") } ?? ""
        guard signedForDistribution, notarized,
              leaf.hasPrefix("1. Developer ID Installer: "), leaf.hasSuffix("(\(team))") else {
            return .failure(Message(text: "安装包的签名不是本程序的开发者，或者没有经过苹果公证，已丢弃。"))
        }
        // 4. Keep it under a readable name for the Installer window.
        let fm = FileManager.default
        let target = folder.appendingPathComponent("ErgouIME-\(update.version).pkg")
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: file, to: target)
        } catch {
            return .failure(Message(text: "没法保存安装包。"))
        }
        return .success(target)
    }

    /// "<TEAMID>.com.codamon.ergou" → TEAMID (both apps are signed by this team).
    nonisolated static var ourTeamID: String? {
        let id = Paths.appGroupID
        guard let dot = id.firstIndex(of: ".") else { return nil }
        let team = String(id[..<dot])
        return team.count == 10 && team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) ? team : nil
    }

    nonisolated private static func pkgutilCheckSignature(_ file: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = ["--check-signature", file.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate {
        weak var owner: UpdateInstaller?
        let purpose: String
        init(owner: UpdateInstaller, purpose: String) { self.owner = owner; self.purpose = purpose }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            Task { @MainActor [owner] in owner?.progress(totalBytesWritten, totalBytesExpectedToWrite) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            let keep = FileManager.default.temporaryDirectory.appendingPathComponent("update-\(UUID().uuidString).pkg")
            let moved = (try? FileManager.default.moveItem(at: location, to: keep)) != nil
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = moved && (200..<300).contains(status)
            if !ok { try? FileManager.default.removeItem(at: keep) }
            Task { @MainActor [owner] in
                owner?.finished(ok ? keep : nil, error: ok ? nil : "下载失败（HTTP \(status)）。")
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            NetworkLog.recordDownload(task, error: error, purpose: purpose)
            guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
            Task { @MainActor [owner] in owner?.finished(nil, error: "下载失败：网络错误。") }
        }
    }
}
