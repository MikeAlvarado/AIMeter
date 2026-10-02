import XCTest
import UsageKit
@testable import AIMeter

/// The status item's text, fill and tint rules, and the style migration.
/// Pure — nothing here renders.
final class MenuBarLabelModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(session: Double = 42, weekly: Double = 18, credits: Bool = false) -> UsageSnapshot {
        var windows = [
            UsageWindow.make(.session, used: session, resetsIn: 80 * 60, now: now),
            UsageWindow.make(.weekly, used: weekly, resetsIn: 3 * 86_400, now: now),
        ]
        windows.append(UsageWindow.make(.modelSpecific("Fable"), used: 7, resetsIn: 3 * 86_400, now: now))
        let spend = credits ? SpendStatus(enabled: true, percent: 12) : nil
        return .make(windows: windows, spend: spend)
    }

    private func make(
        _ style: MenuBarStyle,
        snapshot: UsageSnapshot? = nil,
        displayMode: DisplayMode = .used,
        metric: UsageWindow.Kind = .session,
        metrics: [UsageWindow.Kind] = [.session, .weekly],
        tints: Bool = false,
        countdown: Bool = false,
        accountName: String? = nil
    ) -> MenuBarLabelModel {
        MenuBarLabelModel(
            snapshot: snapshot ?? self.snapshot(), displayMode: displayMode, style: style, metric: metric,
            metrics: metrics, modelSlotFallback: .auto, tintsAtDanger: tints, showsCountdown: countdown,
            accountName: accountName, now: now
        )
    }

    func testGaugeStylesFollowTheDisplayedFigure() {
        let used = make(.gaugeWithPercent)
        XCTAssertEqual(used.text, "42%")
        XCTAssertEqual(used.fraction, 0.42, accuracy: 0.001)
        XCTAssertEqual(used.tint, .normal)

        let remaining = make(.gaugeWithPercent, displayMode: .remaining)
        XCTAssertEqual(remaining.text, "58%")
        XCTAssertEqual(remaining.fraction, 0.58, accuracy: 0.001, "the gauge never contradicts its own label")

        let gaugeOnly = make(.gaugeOnly)
        XCTAssertNil(gaugeOnly.text)
        XCTAssertTrue(gaugeOnly.accessibilityLabel.contains("42%"), "icon-only still speaks the number")
    }

    func testPercentBarAndBatterySpellTheNumber() {
        for style in [MenuBarStyle.percentOnly, .bar, .battery] {
            XCTAssertEqual(make(style).text, "42%", "\(style)")
        }
    }

    func testMultiListsOnlyWindowsTheAccountReports() {
        let label = make(.multi, metrics: [.session, .weekly, .credits])
        XCTAssertEqual(label.text, "S 42% · W 18%", "no credits on this account, so no C")
        XCTAssertEqual(label.fraction, 0.42, accuracy: 0.001, "fill follows the first listed window")

        let withModel = make(.multi, metrics: [.weekly, .modelSpecific("Fable")])
        XCTAssertEqual(withModel.text, "W 18% · F 7%")

        let nothingAvailable = make(.multi, metrics: [.credits])
        XCTAssertEqual(nothingAvailable.text, "S 42%", "falls back to the single metric")

        XCTAssertEqual(make(.multi, snapshot: snapshot(credits: true), metrics: [.session, .weekly, .modelSpecific("Fable"), .credits]).text,
                       "S 42% · W 18% · F 7%", "capped at three")
    }

    func testDangerTintOnlyWhenAskedAndOnlyPastTheThreshold() {
        let hot = snapshot(session: 85)
        XCTAssertEqual(make(.gaugeWithPercent, snapshot: hot).tint, .normal, "off by default")
        XCTAssertEqual(make(.gaugeWithPercent, snapshot: hot, tints: true).tint, .danger)
        XCTAssertEqual(make(.gaugeWithPercent, snapshot: hot, displayMode: .remaining, tints: true).tint, .danger,
                       "the threshold is on usage, whatever is displayed")
        XCTAssertEqual(make(.gaugeWithPercent, tints: true).tint, .normal, "42% used is not red")
        XCTAssertEqual(make(.multi, snapshot: snapshot(weekly: 90), metrics: [.session, .weekly], tints: true).tint, .danger,
                       "any listed window past the threshold")
    }

    func testCountdownAppendsToSingleStylesOnly() {
        XCTAssertEqual(make(.gaugeWithPercent, countdown: true).text, "42% · 1h 20m")
        XCTAssertEqual(make(.gaugeOnly, countdown: true).text, "1h 20m")
        XCTAssertEqual(make(.multi, countdown: true).text, "S 42% · W 18%", "no room in the multi style")
        XCTAssertTrue(make(.gaugeWithPercent, countdown: true).accessibilityLabel.contains("1h 20m"))
    }

    func testAccountNamePrefixesAndIsCut() {
        XCTAssertEqual(make(.gaugeWithPercent, accountName: "Work").text, "Work 42%")
        XCTAssertEqual(make(.gaugeOnly, accountName: "Work").text, "Work")
        XCTAssertEqual(make(.percentOnly, accountName: "Personal account").text, "Personal 42%")
        XCTAssertTrue(make(.percentOnly, accountName: "Personal account").accessibilityLabel.hasPrefix("Personal account — "),
                      "the full name is still spoken")
    }

    func testNoSnapshotIsAnEmptyGauge() {
        let label = MenuBarLabelModel(
            snapshot: nil, displayMode: .used, style: .gaugeWithPercent, metric: .session, metrics: [],
            modelSlotFallback: .auto, tintsAtDanger: true, showsCountdown: true, accountName: "Work", now: now
        )
        XCTAssertEqual(label.fraction, 0)
        XCTAssertEqual(label.text, "Work", "only the name survives — there is no figure to spell")
        XCTAssertEqual(label.tint, .normal)
        XCTAssertEqual(label.accessibilityLabel, "AIMeter — no usage data yet")
    }

    // MARK: Migration

    func testStyleMigratesFromTheOldToggle() {
        XCTAssertEqual(MenuBarStyle.migrated(showsPercentage: true), .gaugeWithPercent)
        XCTAssertEqual(MenuBarStyle.migrated(showsPercentage: false), .gaugeOnly)

        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        XCTAssertEqual(Preferences.load(from: scratch.defaults).menuBarStyle, .gaugeWithPercent, "fresh install")

        scratch.defaults.set(false, forKey: Preferences.Keys.menuBarShowsPercentage)
        XCTAssertEqual(Preferences.load(from: scratch.defaults).menuBarStyle, .gaugeOnly, "old toggle off → gauge only")

        scratch.defaults.set(MenuBarStyle.bar.rawValue, forKey: Preferences.Keys.menuBarStyle)
        XCTAssertEqual(Preferences.load(from: scratch.defaults).menuBarStyle, .bar, "a chosen style wins over the old toggle")

        scratch.defaults.set("nonsense", forKey: Preferences.Keys.menuBarStyle)
        XCTAssertEqual(Preferences.load(from: scratch.defaults).menuBarStyle, .gaugeOnly, "garbage falls back to the migration")
    }

    func testMetricsLoadAndDefault() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        XCTAssertEqual(Preferences.load(from: scratch.defaults).menuBarMetrics, [.session, .weekly])

        scratch.defaults.set(["weekly", "bogus", "credits"], forKey: Preferences.Keys.menuBarMetrics)
        XCTAssertEqual(Preferences.load(from: scratch.defaults).menuBarMetrics, [.weekly, .credits], "unknown keys dropped")

        scratch.defaults.set(["bogus"], forKey: Preferences.Keys.menuBarMetrics)
        XCTAssertEqual(Preferences.load(from: scratch.defaults).menuBarMetrics, [.session, .weekly], "never empty")

        let model = PreferencesModel(defaults: scratch.defaults)
        model.menuBarMetrics = [.session, .modelSpecific("Fable")]
        XCTAssertEqual(Preferences.load(from: scratch.defaults).menuBarMetrics, [.session, .modelSpecific("Fable")], "round-trips through storage keys")
    }
}
