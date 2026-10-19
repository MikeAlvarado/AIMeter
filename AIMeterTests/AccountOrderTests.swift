import XCTest
import UsageKit
@testable import AIMeter

/// "Order by urgency": what counts as urgent, the order it yields, and
/// the model applying it over the registry's own order without writing
/// it.
@MainActor
final class AccountOrderTests: XCTestCase {
    private func snapshot(_ used: Double..., severity: UsageWindow.Severity? = nil) -> UsageSnapshot {
        var windows = used.enumerated().map { index, pct in
            UsageWindow.make(index == 0 ? .session : .weekly, used: pct)
        }
        if let severity, !windows.isEmpty { windows[0].severity = severity }
        return .make(windows: windows)
    }

    func testUrgencyIsTheMostUsedWindowAndAFlagCountsAsFull() {
        XCTAssertEqual(AccountOrder.urgency(of: snapshot(42, 61)), 61)
        XCTAssertEqual(AccountOrder.urgency(of: snapshot(12, severity: .critical)), 100)
        XCTAssertEqual(AccountOrder.urgency(of: snapshot(12, severity: .warning)), 12)
        XCTAssertNil(AccountOrder.urgency(of: nil))
        XCTAssertNil(AccountOrder.urgency(of: .make(windows: [])))
    }

    func testTheMostUrgentGoesFirstTiesKeepTheirOrderAndNoSnapshotGoesLast() {
        let rows: [(String, UsageSnapshot?)] = [
            ("quiet", snapshot(10, 5)), ("none", nil), ("busy", snapshot(73, 18)),
            ("same-a", snapshot(50)), ("same-b", snapshot(50)), ("flagged", snapshot(20, severity: .exceeded)),
        ]
        let ordered = AccountOrder.byUrgency(rows) { $0.1 }.map(\.0)
        XCTAssertEqual(ordered, ["flagged", "busy", "same-a", "same-b", "quiet", "none"])
    }

    func testTheModelOrdersItsAccountsAndLeavesTheRegistryAlone() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let registry = AccountRegistryStore(userDefaults: scratch.defaults)
        registry.add(.managed("personal", name: "Personal"))
        registry.add(.managed("work", name: "Work"))
        let model = UsageModel(registry: registry, platformServices: false)
        model.accounts[0].snapshot = snapshot(42)
        model.accounts[1].snapshot = snapshot(73)

        model.setOrdersByUrgency(true)
        XCTAssertEqual(model.accounts.map(\.id), ["work", "personal"])
        XCTAssertEqual(registry.accounts().map(\.accountID), ["personal", "work"], "the user's order stays underneath")

        model.setOrdersByUrgency(false)
        XCTAssertEqual(model.accounts.map(\.id), ["personal", "work"], "back to the registry's order")
    }
}
