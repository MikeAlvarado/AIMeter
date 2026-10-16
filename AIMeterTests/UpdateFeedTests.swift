#if os(macOS)
import XCTest
@testable import AIMeter

/// The Mac's update feed against a captured GitHub response, and the
/// pure parts of installing.
final class UpdateFeedTests: XCTestCase {
    private func fixture() throws -> UpdateFeed.Release {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "github-release-latest", withExtension: "json")
                ?? bundle.url(forResource: "github-release-latest", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(UpdateFeed.Release.self, from: Data(contentsOf: url))
    }

    func testTheCapturedReleaseDecodes() throws {
        let release = try fixture()
        XCTAssertEqual(release.tagName, "2.0.0")
        XCTAssertFalse(release.draft)
        XCTAssertFalse(release.prerelease)
        let zip = try XCTUnwrap(release.assets.first { $0.name == UpdateFeed.assetName })
        XCTAssertGreaterThan(zip.size, 1_000_000)
        XCTAssertEqual(zip.digest?.hasPrefix("sha256:"), true)
        XCTAssertTrue(zip.browserDownloadURL.absoluteString.hasSuffix("/2.0.0/AIMeter-macOS.zip"))
    }

    func testOnlyANewerVersionIsOffered() throws {
        let release = try fixture()
        let offer = try XCTUnwrap(UpdateFeed.offer(in: release, current: AppVersion("1.6.1")!))
        XCTAssertEqual(offer.version, AppVersion("2.0.0"))
        XCTAssertEqual(offer.sha256?.count, 64, "the hex digest, without its sha256: prefix")
        XCTAssertEqual(offer.page.absoluteString, "https://github.com/MikeAlvarado/AIMeter/releases/tag/2.0.0")
        XCTAssertNil(UpdateFeed.offer(in: release, current: AppVersion("2.0.0")!), "the same version")
        XCTAssertNil(UpdateFeed.offer(in: release, current: AppVersion("2.1.0")!), "an older one")
    }

    func testDraftsPreReleasesAndReleasesWithoutTheZipAreNotOffered() throws {
        let release = try fixture()
        let old = AppVersion("1.0")!
        let draft = UpdateFeed.Release(tagName: "9.0.0", htmlURL: release.htmlURL, draft: true, prerelease: false, assets: release.assets)
        let beta = UpdateFeed.Release(tagName: "9.0.0", htmlURL: release.htmlURL, draft: false, prerelease: true, assets: release.assets)
        let bare = UpdateFeed.Release(tagName: "9.0.0", htmlURL: release.htmlURL, draft: false, prerelease: false, assets: [])
        for candidate in [draft, beta, bare] {
            XCTAssertNil(UpdateFeed.offer(in: candidate, current: old))
        }
    }

    func testTranslocatedCopiesAreNotReplacedInPlace() {
        XCTAssertTrue(UpdateInstaller.isTranslocated("/private/var/folders/x/AppTranslocation/ABC/d/AIMeter.app"))
        XCTAssertFalse(UpdateInstaller.isTranslocated("/Applications/AIMeter.app"))
    }

    func testTheInstallScriptQuotesPathsAndPutsTheOldCopyBackOnFailure() {
        let script = UpdateInstaller.installScript(
            processID: 42,
            app: URL(fileURLWithPath: "/Applications/Mike's AIMeter.app"),
            update: URL(fileURLWithPath: "/tmp/Updates/2.1.0/AIMeter.app"),
            downloads: URL(fileURLWithPath: "/tmp/Updates")
        )
        XCTAssertTrue(script.contains("kill -0 42"))
        XCTAssertTrue(script.contains("app='/Applications/Mike'\\''s AIMeter.app'"), script)
        XCTAssertTrue(script.contains("mv \"$previous\" \"$app\""), "a failed move restores the running copy")
        XCTAssertTrue(
            script.contains("rm -rf \"$app\"\n    mv \"$previous\" \"$app\""),
            "over whatever a failed move left, never inside it"
        )
        XCTAssertTrue(script.contains("rm -rf \"$previous\""), "the previous version is cleaned up")
        XCTAssertTrue(script.hasSuffix("open \"$app\""))
    }
}
#endif
