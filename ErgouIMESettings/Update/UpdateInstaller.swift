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
//   4. the package itself must say it is ErgouIME (identifier of its
//      component) in exactly the advertised version, newer than this one —
//      an older, genuinely signed release renamed to look new is refused
//   5. open it in the system Installer, which shows its own pages and asks
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
    /// Bumped by start and cancel: callbacks and the verification of an
    /// earlier run are ignored (closing the window during 核对 used to open
    /// the Installer anyway; audit 0.4.1 L4).
    private var run = 0

    nonisolated static let packageIdentifier = "com.codamon.inputmethod.Ergou.pkg"

    var isBusy: Bool {
        switch phase {
        case .downloading, .verifying: return true
        default: return false
        }
    }

    nonisolated static var folder: URL { Paths.privateRoot.appendingPathComponent("Updates", isDirectory: true) }

    /// Downloaded packages older than an hour (the update check calls
    /// this). A fresh one may still be open in the Installer.
    nonisolated static func removeOldPackages() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-3600)
        for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if modified.map({ $0 < cutoff }) ?? true { try? fm.removeItem(at: item) }
        }
    }

    func start(_ update: AvailableUpdate) {
        guard !isBusy else { return }
        run += 1
        self.update = update
        phase = .downloading(received: 0, total: update.packageSize)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        let purpose = "下载更新 \(update.version)"
        let delegate = Delegate(owner: self, run: run, purpose: purpose, expectedBytes: update.packageSize)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        // 联网记录: a line when it starts, so a download cut short by
        // quitting is still listed (audit M7).
        NetworkLog.recordStart(purpose: purpose, url: update.packageURL)
        session.downloadTask(with: update.packageURL).resume()
    }

    func cancel() {
        run += 1
        session?.invalidateAndCancel()
        session = nil
        phase = .idle
    }

    fileprivate func progress(_ received: Int64, _ total: Int64, run id: Int) {
        guard id == run, case .downloading = phase else { return }
        phase = .downloading(received: received, total: total > 0 ? total : (update?.packageSize ?? 0))
    }

    fileprivate func finished(_ file: URL?, error: String?, run id: Int) {
        guard id == run else {
            if let file { try? FileManager.default.removeItem(at: file) }
            return
        }
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
                guard id == self.run else {          // cancelled meanwhile: open nothing
                    try? FileManager.default.removeItem(at: file)
                    if case let .success(pkg) = result { try? FileManager.default.removeItem(at: pkg) }
                    return
                }
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
        // 1. The size GitHub announced.
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value
        guard size == update.packageSize else {
            return .failure(Message(text: "下载的安装包大小不对，已丢弃。"))
        }
        // 2. SHA-256 from the release's .sha256 ("<hex>  ErgouIME-x.pkg").
        let purpose = "下载更新校验值 \(update.version)"
        var checksum: (Data, URLResponse)?
        do {
            checksum = try await URLSession(configuration: .ephemeral).data(from: update.checksumURL)
            NetworkLog.record(program: NetworkLog.Program.settings, purpose: purpose, url: checksum?.1.url,
                              sent: NetworkLog.downloadSent(first: update.checksumURL, last: checksum?.1.url),
                              bytesSent: 0, bytesReceived: Int64(checksum?.0.count ?? 0),
                              result: NetworkLog.result(status: (checksum?.1 as? HTTPURLResponse)?.statusCode, error: nil))
        } catch {
            NetworkLog.record(program: NetworkLog.Program.settings, purpose: purpose, url: update.checksumURL,
                              sent: NetworkLog.downloadSent(first: update.checksumURL, last: nil),
                              bytesSent: 0, bytesReceived: 0, result: NetworkLog.result(status: nil, error: error))
        }
        guard let (data, response) = checksum,
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 4096,
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
        guard let report = pkgutil(["--check-signature", file.path]) else {
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
        // 4. It is ErgouIME, in the advertised version, newer than ours
        //    (audit 0.4.1 M5: any notarised package of the team passed, e.g.
        //    an old release renamed to look new → a downgrade).
        guard let info = packageInfo(file), info.identifier == packageIdentifier,
              let inside = AppVersion(info.version), inside == update.version,
              let current = AppVersion.current, inside > current else {
            return .failure(Message(text: "安装包里的程序或版本号和发布页写的不一致，已丢弃。"))
        }
        // 5. Keep it under a readable name for the Installer window.
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

    /// Identifier and version of the package's single component, from its
    /// PackageInfo (inside the signed archive). nil if it cannot be read or
    /// the package has more or fewer than one component.
    nonisolated private static func packageInfo(_ file: URL) -> (identifier: String, version: String)? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pkginfo-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        guard pkgutil(["--expand", file.path, dir.path]) != nil else { return nil }
        let infos = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .map { $0.appendingPathComponent("PackageInfo") }
            .filter { fm.fileExists(atPath: $0.path) }
        guard infos.count == 1, let data = SafeFile.read(infos[0], maxBytes: 1 << 20) else { return nil }
        final class Reader: NSObject, XMLParserDelegate {
            var found: (String, String)?
            var count = 0
            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                        qualifiedName: String?, attributes: [String: String] = [:]) {
                guard name == "pkg-info" else { return }
                count += 1
                if let id = attributes["identifier"], let version = attributes["version"] { found = (id, version) }
            }
        }
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), reader.count == 1, let found = reader.found else { return nil }
        return found
    }

    /// Runs /usr/sbin/pkgutil; its standard output, or nil if it failed.
    nonisolated private static func pkgutil(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate {
        weak var owner: UpdateInstaller?
        let run: Int
        let purpose: String
        let expectedBytes: Int64
        init(owner: UpdateInstaller, run: Int, purpose: String, expectedBytes: Int64) {
            self.owner = owner; self.run = run; self.purpose = purpose; self.expectedBytes = expectedBytes
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            // Never more than the release said (no endless download).
            if totalBytesWritten > expectedBytes { downloadTask.cancel(); return }
            Task { @MainActor [owner, run] in owner?.progress(totalBytesWritten, totalBytesExpectedToWrite, run: run) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            let keep = FileManager.default.temporaryDirectory.appendingPathComponent("update-\(UUID().uuidString).pkg")
            let moved = (try? FileManager.default.moveItem(at: location, to: keep)) != nil
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = moved && (200..<300).contains(status)
            if !ok { try? FileManager.default.removeItem(at: keep) }
            Task { @MainActor [owner, run] in
                owner?.finished(ok ? keep : nil, error: ok ? nil : "下载失败（HTTP \(status)）。", run: run)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            NetworkLog.recordDownload(task, error: error, purpose: purpose)
            guard let error else { return }
            let tooBig = task.countOfBytesReceived > expectedBytes
            if (error as NSError).code == NSURLErrorCancelled, !tooBig { return }
            Task { @MainActor [owner, run] in
                owner?.finished(nil, error: tooBig ? "下载的内容比发布页写的大，已停止。" : "下载失败：网络错误。", run: run)
            }
        }
    }
}
