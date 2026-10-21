import XCTest
import UsageKit
@testable import AIMeter

/// Which window leads an account card (`AccountCardLayout`): the app's
/// Dashboard card, the small widget and each account of the all-accounts
/// widget all draw from this one rule.
final class AccountCardLayoutTests: XCTestCase {
    func testTheMostUsedWindowLeadsAndTheRestKeepTheirOrder() {
        let snapshot = UsageSnapshot.make(windows: [
            .make(.session, used: 42, resetsIn: 3600),
            .make(.weekly, used: 61, resetsIn: 86400),
            .make(.modelSpecific("Top model"), used: 18, resetsIn: 86400),
        ])
        let layout = AccountCardLayout(snapshot: snapshot, modelSlotFallback: .auto)
        XCTAssertEqual(layout.hero.kind, .weekly)
        XCTAssertEqual(layout.heroIndex, 1)
        XCTAssertEqual(layout.others.map(\.kind), [.session, .modelSpecific("Top model")])
    }

    func testATieKeepsTheSessionFirst() {
        let snapshot = UsageSnapshot.make(windows: [
            .make(.session, used: 30, resetsIn: 3600),
            .make(.weekly, used: 30, resetsIn: 86400),
        ])
        let layout = AccountCardLayout(snapshot: snapshot, modelSlotFallback: .hidden)
        XCTAssertEqual(layout.hero.kind, .session)
        XCTAssertEqual(layout.others.map(\.kind), [.weekly])
    }

    func testAFlaggedWindowCountsAsFull() {
        let snapshot = UsageSnapshot.make(windows: [
            .make(.session, used: 80, resetsIn: 3600),
            UsageWindow(kind: .weekly, usedPct: 40, resetsAt: Date().addingTimeInterval(86400), severity: .critical),
        ])
        XCTAssertEqual(AccountCardLayout(snapshot: snapshot, modelSlotFallback: .hidden).hero.kind, .weekly)
    }

    func testBeforeTheFirstFetchThePlaceholderSessionLeads() {
        let layout = AccountCardLayout(snapshot: nil, modelSlotFallback: .auto)
        XCTAssertEqual(layout.hero.kind, .session)
        XCTAssertNil(layout.hero.window)
        XCTAssertEqual(layout.others.map(\.kind), [.weekly])
    }

    func testAQuotaProviderLeadsWithItsMostUsedQuota() {
        let snapshot = UsageSnapshot.make(windows: [
            .make(.quota("premium_interactions"), used: 12, resetsIn: 86400),
            .make(.quota("chat"), used: 55, resetsIn: 86400),
            .make(.quota("completions"), used: 3, resetsIn: 86400),
        ])
        let layout = AccountCardLayout(snapshot: snapshot, modelSlotFallback: .auto)
        XCTAssertEqual(layout.hero.kind, .quota("chat"))
        XCTAssertEqual(layout.others.map(\.kind), [.quota("premium_interactions"), .quota("completions")])
    }
}
