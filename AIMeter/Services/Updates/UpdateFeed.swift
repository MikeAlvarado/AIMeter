#if os(macOS)
import Foundation

/// Where the Mac app learns about a new version: the repository's newest
/// GitHub release and its `AIMeter-macOS.zip`, the notarized build
/// `Scripts/release-mac.sh` publishes. No server of AIMeter's own: the
/// same public release the website's Download button points at. Decoded
/// from a captured response (`AIMeterTests/Fixtures/github-release-latest.json`).
nonisolated enum UpdateFeed {
    static let latestURL = URL(string: "https://api.github.com/repos/MikeAlvarado/AIMeter/releases/latest")!
    static let assetName = "AIMeter-macOS.zip"

    struct Release: Decodable, Equatable, Sendable {
        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", htmlURL = "html_url", draft, prerelease, assets
        }
    }

    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let size: Int
        /// "sha256:<hex>", once GitHub has computed it.
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, browserDownloadURL = "browser_download_url", size, digest
        }
    }

    /// What a release offers this install: a newer version and its Mac zip.
    struct Offer: Equatable, Sendable {
        let version: AppVersion
        let download: URL
        let size: Int
        /// The zip's SHA-256, hex, when the release states one.
        let sha256: String?
        let page: URL
    }

    /// The offer in `release`, or nil: a draft, a pre-release, a version
    /// that isn't newer than `current`, or a release without the Mac zip.
    static func offer(in release: Release, current: AppVersion) -> Offer? {
        guard !release.draft, !release.prerelease,
              let version = AppVersion(release.tagName), version > current,
              let asset = release.assets.first(where: { $0.name == assetName }) else { return nil }
        let sha256 = asset.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst("sha256:".count)) : nil }
        return Offer(version: version, download: asset.browserDownloadURL, size: asset.size, sha256: sha256, page: release.htmlURL)
    }

    static func fetchLatest(from feed: URL = latestURL, session: URLSession = .shared) async throws -> Release {
        var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AIMeter/\(AppVersion.current?.description ?? "0")", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.feed(status: http.statusCode)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}

/// Why an update didn't happen. Shown in Settings → Updates after a check
/// the user asked for; a scheduled check that fails just tries again the
/// next day.
nonisolated enum UpdateError: LocalizedError, Equatable {
    case feed(status: Int)
    case download(status: Int)
    case digest
    case unpack
    case untrusted
    case wrongVersion

    var errorDescription: String? {
        switch self {
        case .feed(let status): String(localized: "GitHub answered \(status).")
        case .download(let status): String(localized: "The download failed (\(status)).")
        case .digest: String(localized: "The download didn't match the release.")
        case .unpack: String(localized: "The download couldn't be opened.")
        case .untrusted: String(localized: "The download isn't signed by AIMeter's developer.")
        case .wrongVersion: String(localized: "The download isn't the version the release announced.")
        }
    }
}
#endif
