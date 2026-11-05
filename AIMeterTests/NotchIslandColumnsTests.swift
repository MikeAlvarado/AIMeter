#if os(macOS)
import XCTest
import SwiftUI
import UsageKit
@testable import AIMeter

/// The expanded island's account lines (`IslandColumns`): equal cells,
/// and that the account rows never lay out wider than the island offers,
/// with the figures of Mike's screenshot of 3.2.0 (2026-10-20), where a
/// `Grid` took 451 pt of the 366 offered and the island cut both ends.
@MainActor
final class NotchIslandColumnsTests: XCTestCase {
    /// Two cells or three, each line is shared edge to edge by cells of one
    /// width with one gap and a separator between them (Mike, 2026-11-05).
    func testAnAccountsCellsAreEquallyWideAndEquallySpaced() {
        let metrics = IslandColumns.Metrics(widest: [2: 120, 3: 96], separatorWidth: 7, gap: 8)
        // Between two cells: 8 + 7 + 8 = 23.
        XCTAssertEqual(metrics.ideal, 3 * 96 + 2 * 23, "the line of three is the widest need")
        XCTAssertEqual(metrics.width(offered: 366), 366)
        XCTAssertEqual(metrics.width(offered: 300), metrics.ideal, "offered less, the ideal")
        XCTAssertEqual(metrics.width(offered: nil), metrics.ideal)

        for count in [2, 3] {
            let cell = metrics.cellWidth(of: count, width: 366)
            let starts = (0..<count).map { metrics.cellX($0, of: count, width: 366) }
            XCTAssertEqual(starts.first, 0)
            XCTAssertEqual(starts.last! + cell, 366, accuracy: 0.001, "the last cell ends at the right edge")
            for index in 1..<count {
                XCTAssertEqual(starts[index] - (starts[index - 1] + cell), 23, accuracy: 0.001, "one gap between every two")
                let separator = metrics.separatorX(index, of: count, width: 366)
                XCTAssertEqual(separator - (starts[index - 1] + cell), starts[index] - (separator + 7), accuracy: 0.001, "the separator centred")
            }
        }
        XCTAssertEqual(metrics.cellWidth(of: 2, width: 366), (366 - 23) / 2)
        XCTAssertEqual(metrics.cellWidth(of: 3, width: 366), (366 - 46) / 3)
    }

    func testOneCellTakesTheWholeLine() {
        let metrics = IslandColumns.Metrics(widest: [1: 80], separatorWidth: 0, gap: 8)
        XCTAssertEqual(metrics.ideal, 80)
        XCTAssertEqual(metrics.cellWidth(of: 1, width: 366), 366)
        XCTAssertEqual(metrics.cellX(0, of: 1, width: 366), 0)
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
