import XCTest
@testable import UsageKit

final class SnapshotStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "UsageKitTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSaveAndLoadRoundtrip() throws {
        let store = SnapshotStore(userDefaults: defaults)
        let snapshot = UsageSnapshot(
            providerID: "claude",
            planName: "pro",
            windows: [UsageWindow(kind: .session, usedPct: 24, resetsAt: Date())]
        )

        try store.save(snapshot)
        let loaded = try XCTUnwrap(store.snapshot(for: "claude"))

        XCTAssertEqual(loaded.providerID, "claude")
        XCTAssertEqual(loaded.planName, "pro")
        XCTAssertEqual(loaded.windows.count, 1)
        XCTAssertEqual(loaded.windows[0].usedPct, 24)
    }

    func testMissingSnapshotReturnsNil() {
        let store = SnapshotStore(userDefaults: defaults)
        XCTAssertNil(store.snapshot(for: "claude"))
    }

    func testSnapshotsAreScopedPerProvider() throws {
        let store = SnapshotStore(userDefaults: defaults)
        try store.save(UsageSnapshot(providerID: "claude", windows: []))

        XCTAssertNotNil(store.snapshot(for: "claude"))
        XCTAssertNil(store.snapshot(for: "openai"))

        store.removeSnapshot(for: "claude")
        XCTAssertNil(store.snapshot(for: "claude"))
    }
}
