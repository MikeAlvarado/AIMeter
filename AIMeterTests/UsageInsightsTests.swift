import XCTest
import UsageKit
@testable import AIMeter

/// What fits in today, and which other account has room.
final class UsageInsightsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTodaysShareIsWhatIsLeftOverTheDaysLeftTodayIncluded() throws {
        // 61 % used, 3 days 4 hours to go: four days share the 39 % left.
        let week = UsageWindow.make(.weekly, used: 61, resetsIn: 3 * 86_400 + 4 * 3_600, now: now)
        XCTAssertEqual(try XCTUnwrap(UsageInsights.dailyAllowance(for: week, now: now)), 9.75, accuracy: 0.001)

        // Its last hours: today is the one day left.
        let lastDay = UsageWindow.make(.weekly, used: 90, resetsIn: 3_600, now: now)
        XCTAssertEqual(UsageInsights.dailyAllowance(for: lastDay, now: now), 10)
    }

    func testNoTodaysShareForASessionAFullWindowOrOneWithNoReset() {
        XCTAssertNil(UsageInsights.dailyAllowance(for: .make(.session, used: 10, resetsIn: 3_600, now: now), now: now))
        XCTAssertNil(UsageInsights.dailyAllowance(for: .make(.weekly, used: 100, resetsIn: 86_400, now: now), now: now))
        XCTAssertNil(UsageInsights.dailyAllowance(for: .make(.weekly, used: 20), now: now))
        XCTAssertNil(UsageInsights.dailyAllowance(for: .make(.weekly, used: 20, resetsIn: -60, now: now), now: now))
    }

    /// A month-long window (Codex Free, a Copilot quota) shares by the
    /// days of its own month.
    func testAMonthLongWindowSharesByItsOwnDays() throws {
        var month = UsageWindow.make(.weekly, used: 40, resetsIn: 20 * 86_400, now: now)
        month.duration = 30 * 86_400
        XCTAssertEqual(try XCTUnwrap(UsageInsights.dailyAllowance(for: month, now: now)), 3, accuracy: 0.001)
    }

    private func entry(_ id: String, _ name: String, used: Double, provider: String = ProviderCatalog.defaultProviderID)
        -> (account: ConnectedAccount, snapshot: UsageSnapshot?) {
        (ConnectedAccount(accountID: id, providerID: provider, displayName: name, credentialStrategy: .managed),
         .make(windows: [.make(.weekly, used: used)]))
    }

    func testRoomPointsAtTheSameServicesAccountWithTheMost() {
        let others = [entry("a", "Personal", used: 92), entry("b", "Work", used: 30), entry("c", "Side", used: 45)]
        let room = UsageInsights.room(forUrgency: 92, providerID: ProviderCatalog.defaultProviderID, accountID: "a", among: others)
        XCTAssertEqual(room, .init(accountID: "b", name: "Work", freePct: 70))
        XCTAssertEqual(room.map(UsageInsights.roomLine), "Work has 70% free")
    }

    func testNoRoomUntilNearlyOutAndNeverAnotherService() {
        let work = entry("b", "Work", used: 30)
        // At 85 % exactly it is not yet red.
        XCTAssertNil(UsageInsights.room(forUrgency: 85, providerID: ProviderCatalog.defaultProviderID, accountID: "a", among: [work]))
        // Another service's account can't stand in for this one.
        let codex = entry("c", "Codex", used: 10, provider: "codex")
        XCTAssertNil(UsageInsights.room(forUrgency: 95, providerID: ProviderCatalog.defaultProviderID, accountID: "a", among: [codex]))
        // Half used or more is no room to point at, nor is no snapshot.
        XCTAssertNil(UsageInsights.room(forUrgency: 95, providerID: ProviderCatalog.defaultProviderID, accountID: "a", among: [entry("b", "Work", used: 50)]))
        let blank = (ConnectedAccount.managed("d", name: "New"), UsageSnapshot?.none)
        XCTAssertNil(UsageInsights.room(forUrgency: 95, providerID: ProviderCatalog.defaultProviderID, accountID: "a", among: [blank]))
    }
}
