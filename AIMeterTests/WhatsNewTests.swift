import XCTest
@testable import AIMeter

/// Versions, and the notes shown after an update: what the app bundles,
/// and which of them a user is due.
final class WhatsNewTests: XCTestCase {
    private func version(_ text: String) -> AppVersion { AppVersion(text)! }

    // MARK: Versions

    func testVersionsCompareNumberByNumber() {
        XCTAssertLessThan(version("2.0.0"), version("2.1.0"))
        XCTAssertLessThan(version("2.9.0"), version("2.10.0"))
        XCTAssertLessThan(version("1.6.1"), version("2.0"))
        XCTAssertEqual(version("2.1"), version("2.1.0"), "a missing part counts as zero")
        XCTAssertEqual(version("v2.1.0"), version("2.1.0"), "a tag's v is not part of the number")
        XCTAssertEqual(version("2.1.0").description, "2.1.0")
    }

    func testVersionsRejectWhatIsNotOne() {
        for text in ["", "two", "2..1", "2.1-beta", "-1.0"] {
            XCTAssertNil(AppVersion(text), text)
        }
    }

    // MARK: The bundled notes

    func testEveryNoteIsInEveryLanguageWithoutEmDashes() throws {
        let notes = try XCTUnwrap(WhatsNew.load(), "WhatsNew.json is bundled and decodes")
        XCTAssertFalse(notes.releases.isEmpty)
        for release in notes.releases {
            XCTAssertNotNil(AppVersion(release.version), release.version)
            XCTAssertFalse(release.items.isEmpty, release.version)
            for item in release.items {
                for table in [item.title, item.detail] {
                    XCTAssertEqual(Set(table.keys), Set(WhatsNew.languages), "\(release.version) \(item.symbol)")
                    for (language, text) in table {
                        XCTAssertFalse(text.isEmpty, "\(release.version) \(language)")
                        XCTAssertFalse(text.contains("—") || text.contains(" – "), "no em dash: \(release.version) \(language)")
                    }
                }
                for platform in item.platforms ?? [] {
                    XCTAssertTrue(["iOS", "macOS"].contains(platform), platform)
                }
                if let feature = item.feature {
                    XCTAssertNotNil(TourFeature(rawValue: feature), "a feature the tour knows: \(feature)")
                }
            }
        }
        let versions = notes.releases.compactMap { AppVersion($0.version) }
        XCTAssertEqual(versions, versions.sorted(by: >), "newest first")
    }

    // MARK: What is due

    private let notes = WhatsNew(releases: [
        WhatsNew.Release(version: "2.2.0", items: [WhatsNewTests.item("b"), WhatsNewTests.item("mac", platforms: ["macOS"]), WhatsNewTests.item("ios", platforms: ["iOS"])]),
        WhatsNew.Release(version: "2.1.0", items: [WhatsNewTests.item("a")]),
    ])

    static func item(_ symbol: String, platforms: [String]? = nil, feature: String? = nil) -> WhatsNew.Item {
        WhatsNew.Item(symbol: symbol, title: ["en": symbol], detail: ["en": symbol], platforms: platforms, feature: feature)
    }

    func testAFreshInstallHasNothingToCatchUpOn() {
        XCTAssertNil(WhatsNew.pending(notes: notes, current: version("2.2.0"), lastSeen: nil, hasPriorInstall: false))
    }

    func testAnUpgradeFromBeforeTheNotesGetsThisVersion() throws {
        let due = try XCTUnwrap(WhatsNew.pending(notes: notes, current: version("2.2.0"), lastSeen: nil, hasPriorInstall: true))
        XCTAssertEqual(due.version, "2.2.0")
        XCTAssertEqual(due.items.map(\.symbol).first, "b")
    }

    func testSkippedVersionsAddUpNewestFirstAndOnlyForThisPlatform() throws {
        let due = try XCTUnwrap(WhatsNew.pending(notes: notes, current: version("2.2.0"), lastSeen: version("2.0.0"), hasPriorInstall: true))
        #if os(macOS)
        XCTAssertEqual(due.items.map(\.symbol), ["b", "mac", "a"])
        #else
        XCTAssertEqual(due.items.map(\.symbol), ["b", "ios", "a"])
        #endif
        XCTAssertNil(WhatsNew.pending(notes: notes, current: version("2.2.0"), lastSeen: version("2.2.0"), hasPriorInstall: true),
                     "already read")
        XCTAssertNil(WhatsNew.pending(notes: notes, current: version("2.3.0"), lastSeen: version("2.2.0"), hasPriorInstall: true),
                     "a version without notes shows nothing")
    }

    func testTextFallsBackToTheLanguageThenEnglish() {
        let table = ["en": "Hello", "es": "Hola", "pt-BR": "Olá", "zh-Hans": "你好"]
        XCTAssertEqual(WhatsNew.text(table, language: "es"), "Hola")
        XCTAssertEqual(WhatsNew.text(table, language: "es-MX"), "Hola")
        XCTAssertEqual(WhatsNew.text(table, language: "pt-PT"), "Olá")
        XCTAssertEqual(WhatsNew.text(table, language: "zh-Hans"), "你好")
        XCTAssertEqual(WhatsNew.text(table, language: "de"), "Hello")
    }
}
