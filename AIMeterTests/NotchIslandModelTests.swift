import XCTest
import UsageKit
@testable import AIMeter

/// The island's label, figure, tint, reset, third-slot, wing and status
/// rules. Pure — nothing here renders.
final class NotchIslandModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(
        session: Double = 42, weekly: Double = 18, model: Bool = true, credits: Bool = false,
        amounts: Bool = false, fetchedAt: Date? = nil
    ) -> UsageSnapshot {
        var windows = [
            UsageWindow.make(.session, used: session, resetsIn: 80 * 60, now: now),
            UsageWindow.make(.weekly, used: weekly, resetsIn: 3 * 86_400, now: now),
        ]
        if model {
            windows.append(UsageWindow.make(.modelSpecific("Fable"), used: 7, resetsIn: 3 * 86_400, now: now))
        }
        let spend = credits
            ? SpendStatus(enabled: true, percent: 12, usedAmount: amounts ? 3 : nil, limitAmount: amounts ? 25 : nil, currency: "USD")
            : nil
        return UsageSnapshot(providerID: ProviderCatalog.defaultProviderID, planName: "max", fetchedAt: fetchedAt ?? now, windows: windows, spend: spend)
    }

    private func input(
        _ id: String = "a", name: String = "Personal", snapshot: UsageSnapshot? = nil,
        reauth: Bool = false, offline: Bool = false, error: String? = nil
    ) -> NotchIslandModel.AccountInput {
        NotchIslandModel.AccountInput(
            account: .managed(id, name: name), snapshot: snapshot ?? self.snapshot(),
            needsReauthentication: reauth, isOffline: offline, lastError: error
        )
    }

    private func make(
        _ inputs: [NotchIslandModel.AccountInput]? = nil,
        primaryID: String? = nil,
        displayMode: DisplayMode = .used,
        resetStyle: ResetStyle = .relative,
        fallback: ModelSlotFallback = .auto,
        showCreditsAmount: Bool = false,
        metrics: [UsageWindow.Kind] = [.session, .weekly],
        glanceMetric: UsageWindow.Kind = .session,
        layout: NotchIslandLayout = .bothSides,
        incident: String? = nil
    ) -> NotchIslandModel {
        NotchIslandModel(
            accounts: inputs ?? [input()], primaryID: primaryID, displayMode: displayMode, resetStyle: resetStyle,
            modelSlotFallback: fallback, showCreditsAmount: showCreditsAmount, metrics: metrics,
            glanceMetric: glanceMetric, layout: layout, incident: incident, now: now
        )
    }

    private func segments(_ island: NotchIslandModel) -> [NotchIslandModel.Segment] {
        island.accounts.first?.segments ?? []
    }

    // MARK: Labels

    func testLabelsFollowTheWindowsLengthNotItsKind() {
        let labels = segments(make()).map(\.label)
        XCTAssertEqual(labels, ["5h", "7d", "Fable"])

        let monthly = UsageWindow(kind: .weekly, usedPct: 10, resetsAt: now.addingTimeInterval(86_400), duration: 30 * 86_400)
        let shortSession = UsageWindow(kind: .session, usedPct: 10, duration: 3 * 3600)
        let island = make([input(snapshot: .make(windows: [shortSession, monthly]))], fallback: .hidden)
        XCTAssertEqual(segments(island).map(\.label), ["3h", "30d"], "a provider's own lengths, no new Kind needed")

        XCTAssertEqual(NotchIslandModel.label(for: .modelSpecific("Everyday model"), duration: nil, compact: true), "Everyd", "cut in the wings")
        XCTAssertEqual(NotchIslandModel.label(for: .modelSpecific("Everyday model"), duration: nil, compact: false), "Everyday model")
        XCTAssertEqual(NotchIslandModel.label(for: .credits, duration: nil, compact: true), "Cr")
    }

    // MARK: Figures

    func testPercentAndFractionFollowTheDisplayMode() {
        let used = segments(make())[0]
        XCTAssertEqual(used.percent, "42%")
        XCTAssertEqual(used.fraction, 0.42, accuracy: 0.001)

        let remaining = segments(make(displayMode: .remaining))[0]
        XCTAssertEqual(remaining.percent, "58%")
        XCTAssertEqual(remaining.fraction, 0.58, accuracy: 0.001, "the bar never contradicts its number")
        XCTAssertTrue(remaining.accessibilityLabel.contains("58%"))
    }

    func testTintTurnsRedAtEightyOrOnSeverity() {
        XCTAssertEqual(segments(make())[0].tint, .normal)
        XCTAssertEqual(segments(make([input(snapshot: snapshot(session: 85))]))[0].tint, .danger)
        XCTAssertEqual(segments(make([input(snapshot: snapshot(session: 85))], displayMode: .remaining))[0].tint, .danger,
                       "the threshold is on usage, whatever is displayed")
        var flagged = snapshot()
        flagged.windows[1].severity = .critical
        XCTAssertEqual(segments(make([input(snapshot: flagged)]))[1].tint, .danger)
    }

    // MARK: Resets

    func testResetValuesFollowTheResetStyle() {
        XCTAssertEqual(segments(make())[0].reset, "1h 20m")
        XCTAssertEqual(segments(make())[1].reset, "3d")
        XCTAssertTrue(segments(make())[0].accessibilityLabel.contains(UsageFormatting.resetLabel(for: now.addingTimeInterval(80 * 60), style: .relative, now: now)))

        let sessionReset = now.addingTimeInterval(80 * 60)
        let absolute = segments(make(resetStyle: .absolute))[0].reset
        XCTAssertEqual(absolute, NotchIslandModel.resetValue(for: sessionReset, style: .absolute, now: now))
        XCTAssertTrue(absolute?.contains(sessionReset.formatted(date: .omitted, time: .shortened)) == true, "the bare clock time, no sentence")

        let idle = UsageWindow(kind: .session, usedPct: 0)
        XCTAssertNil(segments(make([input(snapshot: .make(windows: [idle]))], fallback: .hidden))[0].reset, "an idle session has no reset")
    }

    func testCreditsShowTheAmountOnlyWhenAsked() {
        let withCredits = [input(snapshot: snapshot(model: false, credits: true, amounts: true))]
        XCTAssertNil(segments(make(withCredits))[2].reset)
        let amount = segments(make(withCredits, showCreditsAmount: true))[2].reset
        XCTAssertNotNil(amount)
        XCTAssertEqual(amount, SpendStatus(enabled: true, percent: 12, usedAmount: 3, limitAmount: 25, currency: "USD").amountLabel)
    }

    // MARK: Third slot

    func testThirdSlotFollowsModelSlotFallback() {
        let noModel = input(snapshot: snapshot(model: false))
        let withSpend = input(snapshot: snapshot(model: false, credits: true))
        XCTAssertEqual(segments(make([noModel])).map(\.kind), [.session, .weekly], "auto without spend: two rows")
        XCTAssertEqual(segments(make([withSpend])).map(\.kind), [.session, .weekly, .credits], "auto with spend: credits")
        XCTAssertEqual(segments(make([withSpend], fallback: .hidden)).map(\.kind), [.session, .weekly])
        let forced = segments(make([noModel], fallback: .credits))
        XCTAssertEqual(forced.map(\.kind), [.session, .weekly, .credits])
        XCTAssertEqual(forced[2].percent, "—", "an empty slot keeps its place")
        XCTAssertEqual(forced[2].fraction, 0)
        XCTAssertEqual(segments(make()).map(\.kind), [.session, .weekly, .modelSpecific("Fable")], "a real model window wins")
    }

    // MARK: Wings

    func testCollapsedSplitsTheMetricsByLayout() {
        let both = make().collapsed
        XCTAssertEqual(both.left.map(\.kind), [.session])
        XCTAssertEqual(both.right.map(\.kind), [.weekly])
        XCTAssertNil(both.left[0].reset, "no reset in the wings")

        let left = make(layout: .leftOnly).collapsed
        XCTAssertEqual(left.left.map(\.kind), [.session, .weekly])
        XCTAssertTrue(left.right.isEmpty)

        let right = make(layout: .rightOnly).collapsed
        XCTAssertTrue(right.left.isEmpty)
        XCTAssertEqual(right.right.map(\.kind), [.session, .weekly])

    }

    func testCollapsedListsOnlyWhatThePrimaryReports() {
        let filtered = make(metrics: [.session, .credits, .weekly]).collapsed
        XCTAssertEqual(filtered.left.map(\.kind) + filtered.right.map(\.kind), [.session, .weekly], "no credits on this account")

        let fallback = make(metrics: [.credits], glanceMetric: .weekly).collapsed
        XCTAssertEqual(fallback.left.map(\.kind), [.weekly], "nothing applicable falls back to the glance metric")

        let capped = make([input(snapshot: snapshot(credits: true))], metrics: [.session, .weekly, .modelSpecific("Fable"), .credits]).collapsed
        XCTAssertEqual(capped.left.count + capped.right.count, 3, "capped at three")
        XCTAssertEqual(capped.right.last?.label, "Fable")

        let empty = make([]).collapsed
        XCTAssertTrue(empty.left.isEmpty && empty.right.isEmpty)
        XCTAssertTrue(make([]).accounts.isEmpty)
    }

    func testPrimaryIsThePreferredAccountWhenStillConnected() {
        let two = [input("a", name: "Personal"), input("b", name: "Work", snapshot: snapshot(session: 77))]
        XCTAssertEqual(make(two, primaryID: "b").collapsed.left[0].percent, "77%")
        XCTAssertEqual(make(two, primaryID: "b").primaryAccount?.id, "b")
        XCTAssertEqual(make(two, primaryID: "gone").collapsed.left[0].percent, "42%", "a stale id falls back to the first")
        XCTAssertEqual(make(two).accounts.map(\.id), ["a", "b"], "registry order")
    }

    // MARK: Status

    func testStatusInPriorityOrder() {
        XCTAssertEqual(make().accounts[0].status, .fresh)
        let old = snapshot(fetchedAt: now.addingTimeInterval(-31 * 60))
        XCTAssertEqual(make([input(snapshot: old)]).accounts[0].status, .stale(UsageFormatting.updatedLabel(old.fetchedAt, now: now)))
        XCTAssertEqual(make([input(snapshot: snapshot(fetchedAt: now.addingTimeInterval(-29 * 60)))]).accounts[0].status, .fresh)
        XCTAssertEqual(make([input(offline: true, error: "URLError")]).accounts[0].status, .offline)
        XCTAssertEqual(make([input(error: "HTTP 500: boom")]).accounts[0].status, .error("HTTP 500: boom"), "the raw body")
        XCTAssertEqual(make([input(reauth: true, offline: true, error: "rejected")]).accounts[0].status, .reauth, "a dead login outranks the rest")
    }

    // MARK: Accessibility

    func testAccessibilityNamesTheAccountOnlyWithTwoOrMore() {
        let one = make()
        XCTAssertFalse(one.accessibilityLabel.hasPrefix("Personal"))
        XCTAssertTrue(one.accessibilityLabel.contains("42%"))

        let two = make([input("a", name: "Personal"), input("b", name: "Work")])
        XCTAssertTrue(two.accounts[0].accessibilityLabel.hasPrefix("Personal — "))
        XCTAssertTrue(two.accounts[1].accessibilityLabel.hasPrefix("Work — "))
        XCTAssertTrue(two.accessibilityLabel.contains("; "))

        XCTAssertEqual(make([]).accessibilityLabel, String(localized: "AIMeter — no usage data yet"))
        XCTAssertEqual(make(incident: "Claude reports an incident: Elevated errors").incident, "Claude reports an incident: Elevated errors")
    }
}
