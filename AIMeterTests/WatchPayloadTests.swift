import XCTest
import UsageKit
@testable import AIMeter

final class WatchPayloadTests: XCTestCase {
    private var scratch: ScratchDefaults!

    override func setUp() {
        super.setUp()
        scratch = ScratchDefaults()
    }

    override func tearDown() {
        scratch.wipe()
        super.tearDown()
    }

    /// Whole seconds: a date goes through JSON as a double, which keeps
    /// no more than the clock's sub-microsecond tail would need.
    private let fetchedAt = Date(timeIntervalSince1970: 1_792_990_000)

    private var payload: WatchPayload {
        var prefs = Preferences()
        prefs.displayMode = .remaining
        prefs.glanceMetric = .weekly
        prefs.usageColors = false
        return WatchPayload(
            sentAt: Date(timeIntervalSince1970: 1_793_000_000),
            accounts: [
                .init(accountID: "b", providerID: "claude", displayName: "Work", icon: .symbol("briefcase.fill"),
                      snapshot: UsageSnapshot(
                          providerID: "claude", planName: "pro", fetchedAt: fetchedAt,
                          windows: [UsageWindow(kind: .session, usedPct: 73, resetsAt: fetchedAt.addingTimeInterval(3600))]
                      )),
                .init(accountID: "a", providerID: "claude", displayName: "Personal", icon: nil, snapshot: nil),
            ],
            prefs: .init(prefs)
        )
    }

    func testThePayloadRoundTripsThroughTheSessionDictionary() throws {
        let context = try payload.contextDictionary()
        XCTAssertEqual(context[WatchPayload.versionKey] as? Int, WatchPayload.version)
        let back = try XCTUnwrap(WatchPayload(context: context))
        XCTAssertEqual(back, payload)
        // The order is the Dashboard's, not the ids'.
        XCTAssertEqual(back.accounts.map(\.accountID), ["b", "a"])
        XCTAssertNil(WatchPayload(context: ["something": "else"]))
        XCTAssertNil(WatchPayload(context: [WatchPayload.key: Data("not json".utf8)]))
    }

    /// The Watch keeps the payload in the same stores the phone's widgets
    /// read, so a payload replaces whatever an earlier one left.
    func testApplyingAPayloadReplacesTheWatchStores() throws {
        let registry = AccountRegistryStore(userDefaults: scratch.defaults)
        let snapshots = SnapshotStore(userDefaults: scratch.defaults)
        _ = registry.add(.managed("old", name: "Old"))
        try snapshots.save(.make(windows: [.make(.session, used: 10)]), for: "old")

        payload.apply(registry: registry, snapshots: snapshots, defaults: scratch.defaults)

        XCTAssertEqual(registry.accounts().map(\.accountID), ["b", "a"])
        XCTAssertEqual(registry.account(for: "b")?.displayName, "Work")
        XCTAssertEqual(registry.account(for: "b")?.icon, .symbol("briefcase.fill"))
        XCTAssertEqual(snapshots.snapshot(for: "b")?.windows.first?.usedPct, 73)
        XCTAssertNil(snapshots.snapshot(for: "a"), "an account with no snapshot yet")
        XCTAssertNil(snapshots.snapshot(for: "old"), "an account the phone no longer has")

        let prefs = Preferences.load(from: scratch.defaults)
        XCTAssertEqual(prefs.displayMode, .remaining)
        XCTAssertEqual(prefs.glanceMetric, .weekly)
        XCTAssertFalse(prefs.usageColors)
        XCTAssertEqual(scratch.defaults.object(forKey: WatchPayload.receivedAtKey) as? Date, payload.sentAt)
    }
}
