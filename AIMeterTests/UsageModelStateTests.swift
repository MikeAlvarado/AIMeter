import XCTest
import UsageKit
@testable import AIMeter

/// `UsageModel.apply(_:)` is the per-provider dispatch that turns one
/// `ProviderRefreshResult` into UI state — the whole point of the
/// provider-keyed rewrite is that one provider's failure can't blank
/// another's, and that dispatch logic is exercised here directly rather
/// than through a real network fetch.
@MainActor
final class UsageModelStateTests: XCTestCase {
    func testSuccessfulResultUpdatesSnapshotAndClearsError() {
        let model = UsageModel()

        model.apply(ProviderRefreshResult(
            providerID: "claude",
            snapshot: UsageSnapshot(providerID: "claude", windows: [UsageWindow(kind: .session, usedPct: 10)]),
            error: nil
        ))

        XCTAssertEqual(model.snapshot(for: "claude")?.windows.first?.usedPct, 10)
        XCTAssertNil(model.lastError(for: "claude"))
        XCTAssertFalse(model.needsConnection(for: "claude"))
    }

    func testCredentialsNotFoundFlipsNeedsConnectionWithoutAnError() {
        let model = UsageModel()

        model.apply(ProviderRefreshResult(
            providerID: "claude",
            snapshot: nil,
            error: UsageError.credentialsNotFound("no token stored yet")
        ))

        XCTAssertTrue(model.needsConnection(for: "claude"))
        // Missing credentials shows the connect prompt, not an error banner.
        XCTAssertNil(model.lastError(for: "claude"))
    }

    func testOtherUsageErrorIsSurfacedWithoutFlippingNeedsConnection() {
        let model = UsageModel()
        // `needsConnection`'s initial value differs by platform (macOS
        // assumes connected; iOS checks the real Keychain) — establish a
        // known "connected" baseline explicitly rather than depend on it,
        // so this test only exercises what `.notAuthenticated` itself does.
        model.apply(ProviderRefreshResult(
            providerID: "claude", snapshot: UsageSnapshot(providerID: "claude", windows: []), error: nil
        ))

        model.apply(ProviderRefreshResult(providerID: "claude", snapshot: nil, error: UsageError.notAuthenticated))

        XCTAssertNotNil(model.lastError(for: "claude"))
        XCTAssertFalse(model.needsConnection(for: "claude"))
    }

    func testNonUsageErrorFallsBackToLocalizedDescription() {
        let model = UsageModel()
        struct SomeOtherError: LocalizedError {
            var errorDescription: String? { "boom" }
        }

        model.apply(ProviderRefreshResult(providerID: "claude", snapshot: nil, error: SomeOtherError()))

        XCTAssertEqual(model.lastError(for: "claude"), "boom")
    }

    func testCancelledFetchLeavesExistingStateUntouched() {
        let model = UsageModel()
        model.apply(ProviderRefreshResult(
            providerID: "claude",
            snapshot: UsageSnapshot(providerID: "claude", windows: [UsageWindow(kind: .session, usedPct: 55)]),
            error: nil
        ))

        // A superseded/cancelled fetch reports neither a snapshot nor an
        // error — the prior state must survive untouched.
        model.apply(ProviderRefreshResult(providerID: "claude", snapshot: nil, error: nil))

        XCTAssertEqual(model.snapshot(for: "claude")?.windows.first?.usedPct, 55)
        XCTAssertNil(model.lastError(for: "claude"))
    }

    func testSuccessClearsAPreviousError() {
        let model = UsageModel()
        model.apply(ProviderRefreshResult(providerID: "claude", snapshot: nil, error: UsageError.notAuthenticated))
        XCTAssertNotNil(model.lastError(for: "claude"))

        model.apply(ProviderRefreshResult(
            providerID: "claude",
            snapshot: UsageSnapshot(providerID: "claude", windows: []),
            error: nil
        ))

        XCTAssertNil(model.lastError(for: "claude"))
    }

    func testOneProviderFailureDoesNotAffectAnothersState() {
        let model = UsageModel()
        model.apply(ProviderRefreshResult(
            providerID: "claude",
            snapshot: UsageSnapshot(providerID: "claude", windows: [UsageWindow(kind: .session, usedPct: 20)]),
            error: nil
        ))

        model.apply(ProviderRefreshResult(providerID: "openai", snapshot: nil, error: UsageError.notAuthenticated))

        XCTAssertEqual(model.snapshot(for: "claude")?.windows.first?.usedPct, 20)
        XCTAssertNil(model.lastError(for: "claude"))
        XCTAssertNotNil(model.lastError(for: "openai"))
    }
}
