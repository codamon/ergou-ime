// ErgouIME Settings — download, verify and install a speech model.
// SPDX-License-Identifier: GPL-3.0-only
//
// Runs only after the user confirmed the dialog (Privacy rule 3). Steps:
//   1. download the archive (URLSession; cancellable; progress)
//   2. check its SHA-256 against ModelCatalog
//   3. unpack with /usr/bin/tar (bsdtar: .tar.bz2 or .zip) into a temporary
//      folder in our container
//   4. check every extracted file against SpeechModelFiles (same values the
//      input method checks before loading)
//   5. move the files into the App Group container (Paths.models)
//   6. for the pinyin dictionary: ask the input method to redeploy Rime
// Nothing else is sent; no cookies or caches are kept (ephemeral session).

import Foundation

@MainActor
final class ModelDownloader: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(received: Int64, total: Int64)
        case verifying
        case installing
        case done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var model: SpeechModel?

    var isBusy: Bool {
        switch phase {
        case .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    func start(_ model: SpeechModel) {
        guard !isBusy else { return }
        self.model = model
        phase = .downloading(received: 0, total: model.archiveBytes)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: Delegate(owner: self), delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: model.sourceURL)
        self.task = task
        task.resume()
    }

    /// Back to idle after a finished or failed run (dialog closed).
    func reset() {
        if !isBusy { phase = .idle }
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
        phase = .idle
    }

    fileprivate func progress(_ received: Int64, _ total: Int64) {
        guard case .downloading = phase else { return }
        phase = .downloading(received: received, total: total > 0 ? total : (model?.archiveBytes ?? 0))
    }

    fileprivate func finished(archive: URL?, error: String?) {
        session?.finishTasksAndInvalidate()
        session = nil
        task = nil
        guard let model, let archive else {
            if phase != .idle { phase = .failed(error ?? "下载失败") }
            return
        }
        phase = .verifying
        Task.detached(priority: .userInitiated) {
            let result = Self.install(archive: archive, model: model)
            try? FileManager.default.removeItem(at: archive)
            if result == nil, model.redeploysRime {
                SharedNotifications.post(SharedNotifications.redeployRime)
            }
            await MainActor.run { self.phase = result.map { .failed($0) } ?? .done }
        }
    }

    /// Returns an error message, or nil on success. Runs off the main thread.
    nonisolated private static func install(archive: URL, model: SpeechModel) -> String? {
        let fm = FileManager.default
        guard FileHash.sha256(of: archive) == model.sha256 else {
            return "下载的文件校验不通过（SHA-256 不符），已丢弃。"
        }
        if let name = model.singleFile {
            return installSingle(archive, as: name, model: model)
        }
        let work = fm.temporaryDirectory.appendingPathComponent("model-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let tar = Process()
            tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            // bsdtar detects the format (bzip2 tarball or zip) itself.
            tar.arguments = ["-xf", archive.path, "-C", work.path]
            try tar.run()
            tar.waitUntilExit()
            guard tar.terminationStatus == 0 else { return "解压失败。" }
        } catch {
            return "解压失败。"
        }

        let expected = model.files
        let dest = expected.directory
        let staging = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(expected.directoryName)-new", isDirectory: true)
        try? fm.removeItem(at: staging)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for (name, sha) in expected.files {
                guard let found = find(name, in: work), FileHash.sha256(of: found) == sha else {
                    return "模型文件 \(name) 缺失或校验不通过。"
                }
                let target = staging.appendingPathComponent(name)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: found, to: target)
            }
            try model.id.write(to: staging.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: staging, to: dest)
        } catch {
            try? fm.removeItem(at: staging)
            return "安装失败：没法写入模型目录。"
        }
        return nil
    }

    /// A model that is one file (e.g. .gguf): already checked, just move it.
    nonisolated private static func installSingle(_ file: URL, as name: String, model: SpeechModel) -> String? {
        let fm = FileManager.default
        let dest = model.files.directory
        let staging = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(model.files.directoryName)-new", isDirectory: true)
        do {
            try? fm.removeItem(at: staging)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try fm.moveItem(at: file, to: staging.appendingPathComponent(name))
            try model.id.write(to: staging.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: staging, to: dest)
            return nil
        } catch {
            try? fm.removeItem(at: staging)
            return "安装失败：没法写入模型目录。"
        }
    }

    /// Settings "删除" (the pinyin dictionary): remove the installed files and
    /// tell the input method, which then falls back to the bundled dictionary.
    static func remove(_ model: SpeechModel) {
        try? FileManager.default.removeItem(at: model.files.directory)
        if model.redeploysRime { SharedNotifications.post(SharedNotifications.redeployRime) }
    }

    /// `name` may have a folder ("tokenizer/vocab.json"): match the whole
    /// relative tail, so a same-named file elsewhere in the archive is not taken.
    nonisolated private static func find(_ name: String, in root: URL) -> URL? {
        let parts = name.split(separator: "/").map(String.init)
        let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = items?.nextObject() as? URL {
            if Array(url.pathComponents.suffix(parts.count)) == parts { return url }
        }
        return nil
    }

    /// URLSession delegate; hops back to the main actor.
    private final class Delegate: NSObject, URLSessionDownloadDelegate {
        weak var owner: ModelDownloader?
        init(owner: ModelDownloader) { self.owner = owner }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            Task { @MainActor [owner] in owner?.progress(totalBytesWritten, totalBytesExpectedToWrite) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            // The file at `location` is deleted when this method returns.
            let keep = FileManager.default.temporaryDirectory
                .appendingPathComponent("model-\(UUID().uuidString).download")
            let moved = (try? FileManager.default.moveItem(at: location, to: keep)) != nil
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = moved && (200..<300).contains(status)
            if !ok { try? FileManager.default.removeItem(at: keep) }
            Task { @MainActor [owner] in
                owner?.finished(archive: ok ? keep : nil, error: ok ? nil : "下载失败（HTTP \(status)）。")
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error else { return }
            if (error as NSError).code == NSURLErrorCancelled { return }
            Task { @MainActor [owner] in owner?.finished(archive: nil, error: "下载失败：网络错误。") }
        }
    }
}
