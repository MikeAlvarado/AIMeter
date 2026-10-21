#if os(macOS)
import XCTest
import SwiftUI
import UsageKit
@testable import AIMeter

/// The expanded island's columns (`IslandColumns`): the gaps' arithmetic,
/// and that the account rows never lay out wider than the island offers,
/// with the figures of Mike's screenshot of 3.2.0 (2026-10-20), where a
/// `Grid` took 451 pt of the 366 offered and the island cut both ends.
@MainActor
final class NotchIslandColumnsTests: XCTestCase {
    func testTheSeparatorsShareTheSpareWidthAndTheLastColumnEndsAtTheEdge() {
        let metrics = IslandColumns.Metrics(columnWidths: [66, 84, 96], separatorWidth: 7)
        XCTAssertEqual(metrics.fixed, 260)
        XCTAssertEqual(metrics.ideal(minimumGap: 10), 300)
        XCTAssertEqual(metrics.width(offered: 366, minimumGap: 10), 366)
        XCTAssertEqual(metrics.width(offered: 280, minimumGap: 10), 300, "offered less, the ideal")
        XCTAssertEqual(metrics.width(offered: nil, minimumGap: 10), 300)
        XCTAssertEqual(metrics.width(offered: .infinity, minimumGap: 10), 300)

        let x = metrics.columnX(width: 366, minimumGap: 10)
        XCTAssertEqual(x.columns[0], 0)
        XCTAssertEqual(x.separators[1], 66 + 26.5)
        XCTAssertEqual(x.columns[1], 66 + 26.5 + 7 + 26.5)
        XCTAssertEqual(x.columns[2] + 96, 366, accuracy: 0.001, "the last column ends at the right edge")
        XCTAssertEqual(x.separators[2] - (x.columns[1] + 84), x.columns[2] - (x.separators[2] + 7), accuracy: 0.001, "even gaps")
    }

    func testOneColumnHasNoGap() {
        let metrics = IslandColumns.Metrics(columnWidths: [80], separatorWidth: 0)
        XCTAssertEqual(metrics.ideal(minimumGap: 10), 80)
        XCTAssertEqual(metrics.columnX(width: 366, minimumGap: 10).columns, [0])
    }

    func testTheRowsOfTwoAccountsWithTwoAndThreeWindowsStayInsideTheIsland() throws {
        let island = Self.screenshotIsland()
        let body = NotchIslandGeometry.expandedWidth - 2 * NotchIslandGeometry.Radii.open.top
        let offered = body - 2 * ExpandedContent.horizontalPadding
        for proposal in [offered, offered - 40, body, 600] {
            let renderer = ImageRenderer(content: AccountGrid(accounts: island.accounts, primaryID: "a"))
            renderer.proposedSize = ProposedViewSize(width: proposal, height: nil)
            let size = try XCTUnwrap(renderer.nsImage?.size)
            XCTAssertLessThanOrEqual(size.width, proposal + 0.5, "laid out within the \(proposal) pt offered")
        }
        let renderer = ImageRenderer(content: AccountGrid(accounts: island.accounts, primaryID: "a"))
        renderer.proposedSize = ProposedViewSize(width: offered, height: nil)
        XCTAssertEqual(try XCTUnwrap(renderer.nsImage?.size.width), offered, accuracy: 0.5, "edge to edge")
    }

    func testTheExpandedBodyTakesExactlyItsWidth() throws {
        let island = Self.screenshotIsland()
        let body = NotchIslandGeometry.expandedWidth - 2 * NotchIslandGeometry.Radii.open.top
        let renderer = ImageRenderer(
            content: ExpandedContent(island: island)
                .environment(UsageModel(registry: nil, platformServices: false))
                .environment(PreferencesModel(defaults: UserDefaults(suiteName: "aimeter.tests.columns")!))
        )
        renderer.proposedSize = ProposedViewSize(width: body, height: nil)
        XCTAssertEqual(try XCTUnwrap(renderer.nsImage?.size.width), body, accuracy: 0.5)
        UserDefaults.standard.removePersistentDomain(forName: "aimeter.tests.columns")
    }

    /// Mike's two accounts as the screenshot showed them: one with a
    /// session and a week, one with a session, a week and Fable.
    private static func screenshotIsland() -> NotchIslandModel {
        let now = Date()
        func window(_ kind: UsageWindow.Kind, _ used: Double, _ resetsIn: TimeInterval, _ duration: TimeInterval) -> UsageWindow {
            UsageWindow(kind: kind, usedPct: used, resetsAt: now.addingTimeInterval(resetsIn), duration: duration)
        }
        let first = ConnectedAccount(accountID: "a", providerID: "claude", displayName: "Claude", credentialStrategy: .autoDetected)
        let second = ConnectedAccount(accountID: "b", providerID: "claude", displayName: "BuildPeer", credentialStrategy: .managed)
        let twoWindows = UsageSnapshot(providerID: "claude", planName: "max", windows: [
            window(.session, 4, 13 * 60, 5 * 3600),
            window(.weekly, 0, (4 * 24 + 19) * 3600 + 120, 7 * 86400),
        ])
        let threeWindows = UsageSnapshot(providerID: "claude", windows: [
            window(.session, 14, 13 * 60, 5 * 3600),
            window(.weekly, 17, (24 + 7) * 3600 + 120, 7 * 86400),
            window(.modelSpecific("Fable"), 27, (24 + 7) * 3600 + 120, 7 * 86400),
        ])
        return NotchIslandModel(
            accounts: [.init(account: first, snapshot: twoWindows), .init(account: second, snapshot: threeWindows)],
            primaryID: "a", displayMode: .used, resetStyle: .relative, modelSlotFallback: .auto,
            showCreditsAmount: false, usageColors: true, metrics: [.session, .weekly], glanceMetric: .session,
            layout: .bothSides, incident: nil, now: now
        )
    }
}
#endif
