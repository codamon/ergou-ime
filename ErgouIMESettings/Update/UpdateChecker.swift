// ErgouIME Settings — ask GitHub for the latest release (Shared/Privacy.swift rule 2).
// SPDX-License-Identifier: GPL-3.0-only
//
// One GET to https://api.github.com/repos/<repo>/releases/latest with an
// ephemeral session (no cookies, no cache). The only thing it says about this
// Mac is the IP address and the User-Agent "ErgouIME-Settings/<version>"
// (GitHub requires a User-Agent). The answer is checked strictly: the tag
// must be v<version>, and the package must be ErgouIME-<version>.pkg with a
// .sha256 next to it, both under this repository's release downloads on
// github.com.

import Foundation

struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    /// "0.2.0" or "v0.2.0"; 1–4 numeric parts, nothing else.
    init?(_ text: String) {
        let raw = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let pieces = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.count <= 6, piece.allSatisfy(\.isASCII), let n = Int(piece), n >= 0 else { return nil }
            parts.append(n)
        }
        self.parts = parts
    }

    static var current: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        for i in 0..<n {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

struct AvailableUpdate: Identifiable {
    var id: String { version.description }
    let version: AppVersion
    let title: String
    /// Release notes (Markdown) as published on GitHub.
    let notes: String
    let pageURL: URL
    let packageURL: URL
    let packageSize: Int64
    let checksumURL: URL
}

enum UpdateChecker {
    static let repository = "codamon/ergou-ime"
    static var releasesPage: URL { URL(string: "https://github.com/\(repository)/releases")! }

    enum Result {
        case upToDate(AppVersion)
        case available(AvailableUpdate)
        case failed(String)
    }

    /// Fetches the latest release and records the time of the check
    /// (SettingKey.lastUpdateCheck), whatever the outcome once GitHub answered.
    static func check() async -> Result {
        guard let current = AppVersion.current else { return .failed("读不到当前版本号。") }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ErgouIME-Settings/\(current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        do {
            let (body, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            Paths.sharedDefaults.set(Date(), forKey: SettingKey.lastUpdateCheck)
            guard status == 200 else { return .failed("GitHub 返回 HTTP \(status)，稍后再试。") }
            data = body
        } catch {
            return .failed("连不上 GitHub，检查一下网络。")
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else {
            return .failed("GitHub 返回的内容看不懂。")
        }
        guard let latest = parse(release) else { return .failed("最新的发布里没有可用的安装包。") }
        return latest.version > current ? .available(latest) : .upToDate(current)
    }

    // MARK: - GitHub JSON

    private struct Release: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: String
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let size: Int64
        let browser_download_url: String
    }

    private static func parse(_ release: Release) -> AvailableUpdate? {
        guard release.draft != true, release.prerelease != true,
              release.tag_name.hasPrefix("v"), let version = AppVersion(release.tag_name),
              let page = URL(string: release.html_url), isOurs(page, under: "/\(repository)/releases") else { return nil }
        let pkgName = "ErgouIME-\(version).pkg"
        guard let pkg = release.assets.first(where: { $0.name == pkgName }),
              let sum = release.assets.first(where: { $0.name == pkgName + ".sha256" }),
              let pkgURL = URL(string: pkg.browser_download_url), let sumURL = URL(string: sum.browser_download_url),
              isOurs(pkgURL, under: downloadsPrefix), isOurs(sumURL, under: downloadsPrefix),
              pkg.size > 0, pkg.size < 2_000_000_000 else { return nil }
        return AvailableUpdate(version: version, title: release.name ?? "二狗输入法 \(version)",
                               notes: String((release.body ?? "").prefix(20_000)),
                               pageURL: page, packageURL: pkgURL, packageSize: pkg.size, checksumURL: sumURL)
    }

    private static var downloadsPrefix: String { "/\(repository)/releases/download/" }

    private static func isOurs(_ url: URL, under prefix: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix(prefix)
    }
}
