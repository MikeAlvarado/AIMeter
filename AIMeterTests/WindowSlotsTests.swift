import XCTest
import UsageKit
@testable import AIMeter

final class WindowSlotsTests: XCTestCase {
    private let now = Date()

    func testRealModelWindowTakesTheThirdSlot() {
        let snapshot = UsageSnapshot.make(windows: [
            .make(.session, used: 10, resetsIn: 3600, now: now),
            .make(.weekly, used: 20, resetsIn: 86400, now: now),
            .make(.modelSpecific("Fable"), used: 5, resetsIn: 86400, now: now),
        ])
        let slots = WindowSlots(snapshot: snapshot, modelSlotFallback: .hidden).slots
        XCTAssertEqual(slots.map(\.kind), [.session, .weekly, .modelSpecific("Fable")])
    }

    func testHiddenFallbackDropsTheThirdSlot() {
        let snapshot = UsageSnapshot.make(windows: [.make(.session, used: 10), .make(.weekly, used: 20)])
        XCTAssertEqual(WindowSlots(snapshot: snapshot, modelSlotFallback: .hidden).slots.count, 2)
    }

    func testCreditsFallbackKeepsThreeSlotsEvenWithoutSpend() {
        let snapshot = UsageSnapshot.make(windows: [.make(.session, used: 10), .make(.weekly, used: 20)])
        let slots = WindowSlots(snapshot: snapshot, modelSlotFallback: .credits).slots
        XCTAssertEqual(slots.map(\.kind), [.session, .weekly, .credits])
        XCTAssertNil(slots[2].window)
    }

    func testAutoShowsCreditsExactlyWhenSpendIsEnabled() {
        let bare = UsageSnapshot.make(windows: [.make(.session, used: 10), .make(.weekly, used: 20)])
        XCTAssertEqual(WindowSlots(snapshot: bare, modelSlotFallback: .auto).slots.count, 2)

        let withSpend = UsageSnapshot.make(
            windows: [.make(.session, used: 10), .make(.weekly, used: 20)],
            spend: SpendStatus(enabled: true, percent: 40)
        )
        let slots = WindowSlots(snapshot: withSpend, modelSlotFallback: .auto).slots
        XCTAssertEqual(slots.last?.kind, .credits)
        XCTAssertEqual(slots.last?.window?.usedPct, 40)
    }

    func testMissingWindowsKeepTheirSlots() {
        let slots = WindowSlots(snapshot: nil, modelSlotFallback: .auto).slots
        XCTAssertEqual(slots.map(\.kind), [.session, .weekly])
        XCTAssertTrue(slots.allSatisfy { $0.window == nil })
    }

    func testResetLineShowsOnceUnderAGroupSharingOneDate() {
        let weeklyReset = now.addingTimeInterval(86400)
        let snapshot = UsageSnapshot.make(windows: [
            .make(.session, used: 10, resetsIn: 3600, now: now),
            UsageWindow(kind: .weekly, usedPct: 20, resetsAt: weeklyReset),
            UsageWindow(kind: .modelSpecific("Fable"), usedPct: 5, resetsAt: weeklyReset),
        ])
        let slots = WindowSlots(snapshot: snapshot, modelSlotFallback: .auto).slots
        XCTAssertTrue(WindowSlots.showsReset(at: 0, in: slots))
        XCTAssertFalse(WindowSlots.showsReset(at: 1, in: slots), "weekly shares its date with the model window")
        XCTAssertTrue(WindowSlots.showsReset(at: 2, in: slots))
    }

    func testNoResetLineWithoutADate() {
        let slots = WindowSlots(snapshot: UsageSnapshot.make(windows: [.make(.session, used: 0)]), modelSlotFallback: .hidden).slots
        XCTAssertFalse(WindowSlots.showsReset(at: 0, in: slots))
    }
}
