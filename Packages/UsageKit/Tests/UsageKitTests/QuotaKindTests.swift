import XCTest
@testable import UsageKit

/// The named-quota kind (`UsageWindow.Kind.quota`) and the length a
/// periodic window advances a missing reset by.
final class QuotaKindTests: XCTestCase {
    func testStorageKeyAndCodableRoundTrip() throws {
        let kind = UsageWindow.Kind.quota("premium_interactions")
        XCTAssertEqual(kind.storageKey, "quota.premium_interactions")
        XCTAssertEqual(UsageWindow.Kind(storageKey: "quota.premium_interactions"), kind)
        XCTAssertNil(UsageWindow.Kind(storageKey: "quota"))
        XCTAssertTrue(kind.isQuota)
        XCTAssertFalse(kind.isModelSpecific)
        XCTAssertTrue(UsageWindow.Kind.modelSpecific("Fable").isModelSpecific)

        let data = try JSONEncoder().encode(kind)
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: data), ["type": "quota", "quota": "premium_interactions"])
        XCTAssertEqual(try JSONDecoder().decode(UsageWindow.Kind.self, from: data), kind)
    }

    func testAQuotaHasNoDefaultLengthOnlyTheProvidersOwn() {
        XCTAssertNil(UsageWindow(kind: .quota("chat"), usedPct: 0).effectiveDuration)
        XCTAssertEqual(UsageWindow(kind: .quota("chat"), usedPct: 0, duration: 30 * 86400).effectiveDuration, 30 * 86400)
    }

    func testAMonthlyWindowAdvancesAMissingResetByItsOwnLength() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-3600)
        let month: TimeInterval = 30 * 86400
        let previous = UsageSnapshot(providerID: "codex", windows: [
            UsageWindow(kind: .weekly, usedPct: 50, resetsAt: old, duration: month),
            UsageWindow(kind: .quota("chat"), usedPct: 50, resetsAt: old, duration: month),
        ])
        let fresh = UsageSnapshot(providerID: "codex", windows: [
            UsageWindow(kind: .weekly, usedPct: 0, resetsAt: nil, duration: month),
            UsageWindow(kind: .quota("chat"), usedPct: 0, resetsAt: nil, duration: month),
        ])

        let filled = fresh.fillingMissingResets(from: previous, now: now)

        XCTAssertEqual(filled.weeklyWindow?.resetsAt, old.addingTimeInterval(month))
        XCTAssertEqual(filled.quotaWindows.first?.resetsAt, old.addingTimeInterval(month))
    }
}
