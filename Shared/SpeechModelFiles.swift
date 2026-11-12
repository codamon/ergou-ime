// ergou-ime — expected files of each speech model (shared by both targets).
// SPDX-License-Identifier: GPL-3.0-only
//
// ErgouIME Settings downloads models into the App Group container; the input
// method loads them from there. Settings has network access, so the input
// method does not trust what it finds: it checks these SHA-256 values (fixed
// in the code, not read from the container) before handing the files to
// onnxruntime, which parses them (Privacy rule 9).
//
// No URLs here: the input method never needs them (ErgouIMESettings/Model/
// ModelCatalog.swift has the download source).

import CryptoKit
import Foundation

struct SpeechModelFiles {
    /// Folder name under Paths.models.
    let directoryName: String
    /// File name → SHA-256 (lowercase hex).
    let files: [String: String]

    static let senseVoiceSmallInt8 = SpeechModelFiles(
        directoryName: "sense-voice",
        files: [
            // From sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2
            // (archive SHA-256 7305f790…8e63), measured on D's Mac 2026-11-09.
            "model.int8.onnx": "12ca1a2ae7ecf3e0019ef2822307ee0b5cadc9196569e379b4c4026f8205276d",
            "tokens.txt": "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc",
        ])

    /// The accurate recogniser (final results). Keys may contain one
    /// subfolder ("tokenizer/…"), kept as is when installing.
    static let qwen3ASR06BInt8 = SpeechModelFiles(
        directoryName: "qwen3-asr",
        files: [
            // From sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2
            // (archive SHA-256 393f8a14…ee96), measured on D's Mac 2026-11-10.
            "conv_frontend.onnx": "d22dc4423e0940e49884e903d2ea2f7e5567c14fc1aed97e4e26d6b8f208ef9e",
            "encoder.int8.onnx": "60748d3e6744a57c9c91e1b17424a6c2990567e8adceb0783940c03ed98fa9d9",
            "decoder.int8.onnx": "4f6885be5959ae26af3089d38ee7972c5fafbeeb1cf8d5e76eab6d8b61ca5771",
            "tokenizer/vocab.json": "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910",
            "tokenizer/merges.txt": "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5",
            "tokenizer/tokenizer_config.json": "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c",
        ])

    static let punctuationCTTransformerInt8 = SpeechModelFiles(
        directoryName: "punctuation",
        files: [
            // From sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8.tar.bz2
            // (archive SHA-256 c0d5aa5f…a6e1), measured on D's Mac 2026-11-09.
            "model.int8.onnx": "65a3fb9f5ad7bfb96bf69e0dc4481df97f6ee60513c1d94ce981ba6effd524b1",
        ])

    /// 拼音大词库: rime-ice (雾凇拼音) 2026.06.30, only the character table and
    /// the base + ext word lists (about 89 万 entries). Not a speech model, but
    /// downloaded, checked and installed the same way. The input method copies
    /// these files into its own Rime user directory (after checking them
    /// again) and imports them from ergou_pinyin_dict.dict.yaml
    /// (ErgouIME/Engine/PinyinDictionary.swift).
    static let pinyinDictRimeIce = SpeechModelFiles(
        directoryName: "pinyin-dict",
        files: [
            // From cn_dicts.zip of rime-ice release 2026.06.30
            // (archive SHA-256 4e196199…4720), measured 2026-11-10.
            "cn_dicts/8105.dict.yaml": "d84a9e18a73a3eadc1b267745f833f5550ee7e2693b6d4af9e058c6e7ce56363",
            "cn_dicts/base.dict.yaml": "5a10ef44d5939071c026d954e181c5ebea2b96468da84da391966866d12cbe9f",
            "cn_dicts/ext.dict.yaml": "436a551937c496c5d6a46e95f8858d239d226a2204c2d64c8beefbff744f6bdd",
        ])

    /// 腾讯词库: optional extra for 拼音大词库 (about 98 万 more words, from
    /// rime-ice's tencent.dict.yaml). Same archive, its own folder, so it can
    /// be added or removed without touching 拼音大词库. Used only together
    /// with pinyinDictRimeIce (it has no character table of its own).
    static let pinyinDictTencent = SpeechModelFiles(
        directoryName: "pinyin-dict-tencent",
        files: [
            // Same cn_dicts.zip (rime-ice 2026.06.30), measured 2026-11-10.
            "cn_dicts/tencent.dict.yaml": "a57c5d1bdd0f4803cc2747b06447992eb8aa0f7f868404b78a0953f08cc0a7c2",
        ])

    /// 整句模型 (librime-octagram grammar), one of two; the user picks one in
    /// Settings (only one grammar can be active). Measured 2026-11-11 with
    /// 拼音大词库 on 121 everyday clauses: whole clause right 65 % without a
    /// model, 81 % with this one, 83 % with wanxiang (docs/DESIGN.md).
    /// The input method copies the file into its Rime user directory, checks
    /// the copy, then removes the downloaded original to save disk space
    /// (GrammarModel.swift); VERSION stays as the "installed" marker.
    static let grammarCompact = SpeechModelFiles(
        directoryName: "grammar-compact",
        files: [
            // rime-octagram-data release 20260712, zh-hans-t-essay-bgw-compact.gram
            // (41 MB, LGPL-3.0), measured 2026-11-11.
            "zh-hans-t-essay-bgw-compact.gram": "d3cb2438c1fdcd6a855dd6ca8f5c1060a29273c6b64c2c2c69af67cd71b6aa7e",
        ])

    static let grammarWanxiang = SpeechModelFiles(
        directoryName: "grammar-wanxiang",
        files: [
            // RIME-LMDG release LTS (the file uploaded there 2026-11-10), wanxiang-lts-zh-hans.gram
            // (418 MB, CC-BY-4.0), measured 2026-11-11.
            "wanxiang-lts-zh-hans.gram": "3457b69f5fe0fc4f5d211c878bbfa2e2361b90639952c9845c8e31e9d047cde6",
        ])

    /// Checks every file against its fixed SHA-256. Reads the files only when
    /// they changed since the last successful check (VerifiedFiles).
    var isIntact: Bool {
        files.allSatisfy { VerifiedFiles.shared.matches(url($0.key), sha256: $0.value) }
    }

    var directory: URL { Paths.models.appendingPathComponent(directoryName, isDirectory: true) }

    func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    var isPresent: Bool {
        files.keys.allSatisfy { FileManager.default.fileExists(atPath: url($0).path) }
    }

    /// This process's own verified copies, for LOADING (audit 0.4.1 M3).
    ///
    /// Checking a file in the App Group and then handing its path to
    /// onnxruntime or llama.cpp leaves a window in which whoever can write
    /// the group container swaps the file. So each process clones the files
    /// into its private container (APFS clone: instant, no extra disk
    /// space), checks the CLONES against the fixed SHA-256 values, and
    /// loads only those. Nobody else can write the private container, and a
    /// clone does not change when its original does. The folder holds
    /// exactly the hashed files, so a library that reads optional extra
    /// files from a model folder finds none.
    ///
    /// nil: not installed, or a file failed its check. Deleting the model in
    /// Settings (the originals) removes the private copies on the next call.
    func verifiedPrivateCopy() -> URL? {
        Self.removeOrphanedPrivateCopies()
        let fm = FileManager.default
        let dir = Self.privateCopies.appendingPathComponent(directoryName, isDirectory: true)
        guard isPresent else {
            if fm.fileExists(atPath: dir.path) { try? fm.removeItem(at: dir) }
            return nil
        }
        for (name, sha) in files {
            let copy = dir.appendingPathComponent(name)
            if VerifiedFiles.shared.matches(copy, sha256: sha) { continue }
            try? fm.removeItem(at: copy)
            try? fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard SafeFile.cloneOrCopy(from: url(name), to: copy),
                  VerifiedFiles.shared.matches(copy, sha256: sha) else {
                try? fm.removeItem(at: copy)
                return nil
            }
        }
        return dir
    }
}

extension SpeechModelFiles {
    static var privateCopies: URL { Paths.privateRoot.appendingPathComponent("VerifiedModels", isDirectory: true) }

    /// Private clones whose model is gone from the App Group (deleted in
    /// Settings or by hand): once the original is deleted a clone is the
    /// only copy and takes real disk space. Called at launch and before
    /// every load; cheap (a directory listing).
    static func removeOrphanedPrivateCopies() {
        let fm = FileManager.default
        for dir in (try? fm.contentsOfDirectory(at: privateCopies, includingPropertiesForKeys: nil)) ?? [] {
            let original = Paths.models.appendingPathComponent(dir.lastPathComponent, isDirectory: true)
            if !fm.fileExists(atPath: original.path) { try? fm.removeItem(at: dir) }
        }
    }
}

/// File operations for data another process may be swapping under us.
enum SafeFile {
    /// Copies a file's CONTENT into a new file at `to` (which must not
    /// exist) and returns the SHA-256 of the bytes written. Whatever `from`
    /// is or becomes — a link, a file replaced half-way — the result is a
    /// regular file of ours whose hash is the returned one.
    static func copyContent(from: URL, to: URL) -> String? {
        // O_NONBLOCK: opening a FIFO planted at the path must not hang.
        let input = open(from.path, O_RDONLY | O_NONBLOCK)
        guard input >= 0 else { return nil }
        defer { close(input) }
        var st = stat()
        guard fstat(input, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        let output = open(to.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard output >= 0 else { return nil }
        var ok = true
        defer {
            close(output)
            if !ok { unlink(to.path) }
        }
        var hasher = SHA256Hasher()
        var buffer = [UInt8](repeating: 0, count: 1 << 20)
        while true {
            let n = Darwin.read(input, &buffer, buffer.count)
            if n == 0 { break }
            guard n > 0 else { ok = false; return nil }
            hasher.update(Data(buffer[0..<n]))
            var off = 0
            while off < n {
                let w = buffer.withUnsafeBytes { write(output, $0.baseAddress! + off, n - off) }
                guard w > 0 else { ok = false; return nil }
                off += w
            }
        }
        return hasher.finalize()
    }

    /// APFS clone (the link itself if `from` is one: the caller must check
    /// the result with VerifiedFiles, which accepts regular files only);
    /// falls back to a content copy on other file systems or volumes.
    static func cloneOrCopy(from: URL, to: URL) -> Bool {
        if clonefile(from.path, to.path, UInt32(CLONE_NOFOLLOW)) == 0 { return true }
        return copyContent(from: from, to: to) != nil
    }

    /// A small regular file, read through one descriptor: not a link, not a
    /// FIFO, at most `maxBytes` (audit L7, L11).
    static func read(_ url: URL, maxBytes: Int) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size <= off_t(maxBytes) else {
            close(fd)
            return nil
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes else { return nil }
        return data
    }
}

enum FileHash {
    /// Streaming SHA-256 of a file, lowercase hex. nil if it cannot be read.
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256Hasher()
        while true {
            let chunk = (try? handle.read(upToCount: 4 << 20)) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(chunk)
        }
        return hasher.finalize()
    }
}

struct SHA256Hasher {
    private var inner = SHA256()
    mutating func update(_ data: Data) { inner.update(data: data) }
    func finalize() -> String { inner.finalize().map { String(format: "%02x", $0) }.joined() }
}

/// Remembers files that passed their SHA-256 check, keyed by a fingerprint
/// that any change to the file alters: inode, size, modification time and
/// status-change time (ctime). ctime is set by the kernel on every write or
/// metadata change and cannot be set back with utimes(), so a file replaced
/// or edited by another process is hashed again. Stored in this process's
/// own sandbox container (Paths.privateRoot), which other programs cannot
/// write. Saves ~2.5 s per launch for a 4.7 GB model (D's Mac, 2026-11-09).
final class VerifiedFiles {
    static let shared = VerifiedFiles()

    private struct Entry: Codable, Equatable {
        var inode: UInt64, size: Int64, mtime: Double, ctime: Double, sha256: String
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let store = Paths.privateRoot.appendingPathComponent("verified-files.json")

    private init() {
        if let data = try? Data(contentsOf: store),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
    }

    func matches(_ url: URL, sha256 expected: String) -> Bool {
        guard let print = fingerprint(url, sha256: expected) else { return false }
        lock.lock()
        let known = entries[url.path] == print
        lock.unlock()
        if known { return true }
        guard FileHash.sha256(of: url) == expected,
              fingerprint(url, sha256: expected) == print else { return false }   // unchanged while hashing
        lock.lock()
        entries[url.path] = print
        let data = try? JSONEncoder().encode(entries)
        lock.unlock()
        try? FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data?.write(to: store, options: .atomic)
        return true
    }

    private func fingerprint(_ url: URL, sha256: String) -> Entry? {
        var st = stat()
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        func seconds(_ t: timespec) -> Double { Double(t.tv_sec) + Double(t.tv_nsec) / 1e9 }
        return Entry(inode: UInt64(st.st_ino), size: Int64(st.st_size),
                     mtime: seconds(st.st_mtimespec), ctime: seconds(st.st_ctimespec), sha256: sha256)
    }
}
