import XCTest
@testable import UsageKit

/// Opt-in integration test against the real endpoint with the local Claude
/// Code login. Never runs in CI: requires AIMETER_LIVE_TEST=1.
///
///     AIMETER_LIVE_TEST=1 swift test --filter LiveClaudeProviderTests
final class LiveClaudeProviderTests: XCTestCase {
    func testFetchUsageAgainstRealAccount() async throws {
        #if os(macOS)
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AIMETER_LIVE_TEST"] == "1",
            "live test disabled (set AIMETER_LIVE_TEST=1 to run)"
        )

        let provider = ClaudeProvider(credentialSource: ClaudeCodeLocalCredentialSource())
        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.providerID, "claude")
        XCTAssertFalse(snapshot.windows.isEmpty)
        XCTAssertNotNil(snapshot.sessionWindow)

        for window in snapshot.windows {
            XCTAssertGreaterThanOrEqual(window.usedPct, 0)
            XCTAssertLessThanOrEqual(window.usedPct, 100)
        }

        print("live snapshot: plan=\(snapshot.planName ?? "?") windows=\(snapshot.windows)")
        #else
        throw XCTSkip("live test is macOS-only")
        #endif
    }
}
