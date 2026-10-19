import XCTest
@testable import AIMeter

/// The feedback row's link: the project's new-issue page, the version and
/// the system in the text, nothing else.
final class FeedbackSettingsTests: XCTestCase {
    func testTheIssueLinkCarriesTheVersionAndTheSystem() throws {
        let url = FeedbackSettings.issueURL(version: "3.2.0 (1)", system: "iOS 27.0")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/MikeAlvarado/AIMeter/issues/new")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.map(\.name), ["body"])
        XCTAssertEqual(items[0].value, "AIMeter 3.2.0 (1), iOS 27.0\n\n")
    }

    func testTheRunningVersionAndSystemAreNamed() {
        XCTAssertTrue(FeedbackSettings.runningVersion.contains("("), FeedbackSettings.runningVersion)
        #if os(macOS)
        XCTAssertTrue(FeedbackSettings.runningSystem.hasPrefix("macOS "), FeedbackSettings.runningSystem)
        #else
        XCTAssertTrue(FeedbackSettings.runningSystem.contains("OS "), FeedbackSettings.runningSystem)
        #endif
    }
}
