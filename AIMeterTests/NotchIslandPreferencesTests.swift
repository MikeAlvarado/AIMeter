import XCTest
import UsageKit
@testable import AIMeter

/// The island's preference keys (presence-checked defaults, round trips),
/// the status-item coupling, the one-time upgrade step, and the
/// per-platform appearance default.
final class NotchIslandPreferencesTests: XCTestCase {
    func testDefaultsAndPresenceCheck() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let fresh = Preferences.load(from: scratch.defaults)
        XCTAssertFalse(fresh.notchIslandEnabled, "off until the migration decides from the hardware")
        XCTAssertFalse(fresh.notchIslandRevealed)
        XCTAssertFalse(fresh.notchIslandDiscovered)
        XCTAssertTrue(fresh.notchIslandExpandsOnHover)
        XCTAssertEqual(fresh.notchIslandLayout, .bothSides, "the wings open on both sides of the notch")
        XCTAssertEqual(fresh.notchIslandMetrics, [.session, .weekly])
        XCTAssertFalse(fresh.notchIslandMigrated)

        scratch.defaults.set(true, forKey: Preferences.Keys.notchIslandEnabled)
        scratch.defaults.set(false, forKey: Preferences.Keys.notchIslandExpandsOnHover)
        XCTAssertTrue(Preferences.load(from: scratch.defaults).notchIslandEnabled)
        XCTAssertFalse(Preferences.load(from: scratch.defaults).notchIslandExpandsOnHover, "a written false is honored")
    }

    func testLayoutAndMetricsRoundTrip() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let model = PreferencesModel(defaults: scratch.defaults)
        model.notchIslandLayout = .rightOnly
        model.notchIslandMetrics = [.weekly, .modelSpecific("Fable"), .credits]
        let reloaded = Preferences.load(from: scratch.defaults)
        XCTAssertEqual(reloaded.notchIslandLayout, .rightOnly)
        XCTAssertEqual(reloaded.notchIslandMetrics, [.weekly, .modelSpecific("Fable"), .credits])

        scratch.defaults.set(["nonsense"], forKey: Preferences.Keys.notchIslandMetrics)
        XCTAssertEqual(Preferences.load(from: scratch.defaults).notchIslandMetrics, [.session, .weekly], "never empty")
        scratch.defaults.set("sideways", forKey: Preferences.Keys.notchIslandLayout)
        XCTAssertEqual(Preferences.load(from: scratch.defaults).notchIslandLayout, .bothSides)
    }

    func testTurningTheIslandOnHidesTheStatusItemAndOffBringsItBack() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let model = PreferencesModel(defaults: scratch.defaults)
        XCTAssertTrue(model.statusItemVisible)
        model.setNotchIsland(enabled: true)
        XCTAssertTrue(model.notchIslandEnabled)
        XCTAssertFalse(model.statusItemVisible)
        XCTAssertFalse(Preferences.load(from: scratch.defaults).statusItemVisible, "written through")
        model.setNotchIsland(enabled: false)
        XCTAssertFalse(model.notchIslandEnabled)
        XCTAssertTrue(model.statusItemVisible)
    }

    func testUpgradeStepDecidesFromTheHardwareExactlyOnce() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        AccountMigration.migrateNotchIslandIfNeeded(defaults: scratch.defaults, hasNotch: true)
        var prefs = Preferences.load(from: scratch.defaults)
        XCTAssertTrue(prefs.notchIslandEnabled)
        XCTAssertTrue(prefs.statusItemVisible, "the icon stays until the island is discovered")
        XCTAssertTrue(prefs.notchIslandMigrated)

        // The user turns it off; the next launch leaves it.
        scratch.defaults.set(false, forKey: Preferences.Keys.notchIslandEnabled)
        AccountMigration.migrateNotchIslandIfNeeded(defaults: scratch.defaults, hasNotch: true)
        prefs = Preferences.load(from: scratch.defaults)
        XCTAssertFalse(prefs.notchIslandEnabled, "never touched again")

        let plain = ScratchDefaults()
        defer { plain.wipe() }
        AccountMigration.migrateNotchIslandIfNeeded(defaults: plain.defaults, hasNotch: false)
        XCTAssertFalse(Preferences.load(from: plain.defaults).notchIslandEnabled, "no notch: the drawn island is opt-in")
    }

    func testFormHeightAndHidingOptionsDefaultsAndPresenceCheck() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let fresh = Preferences.load(from: scratch.defaults)
        XCTAssertEqual(fresh.notchIslandForm, .notch, "a drawn notch unless the user picks the pill")
        XCTAssertEqual(fresh.notchIslandHeightMode, .menuBar)
        XCTAssertEqual(fresh.notchIslandCustomHeight, 36)
        XCTAssertEqual(fresh.notchIslandHoverDelay, NotchIslandInteraction.defaultDwellSeconds)
        XCTAssertFalse(fresh.notchIslandHidesUntilHover)
        XCTAssertTrue(fresh.notchIslandHidesInFullScreen, "on by default")
        XCTAssertFalse(fresh.notchIslandHiddenFromCapture, "captures show it unless asked")
        XCTAssertEqual(fresh.notchIslandOptions, NotchIslandGeometry.Options(form: .notch, height: nil))

        scratch.defaults.set(false, forKey: Preferences.Keys.notchIslandHidesInFullScreen)
        XCTAssertFalse(Preferences.load(from: scratch.defaults).notchIslandHidesInFullScreen, "a written false is honored")
    }

    func testFormAndHeightRoundTripAndShapeTheOptions() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let model = PreferencesModel(defaults: scratch.defaults)
        model.notchIslandForm = .pill
        model.notchIslandHeightMode = .custom
        model.notchIslandCustomHeight = 30
        model.notchIslandHoverDelay = 0.6
        model.notchIslandHidesUntilHover = true
        model.notchIslandHiddenFromCapture = true
        XCTAssertEqual(model.notchIslandOptions, NotchIslandGeometry.Options(form: .pill, height: 30))

        let reloaded = Preferences.load(from: scratch.defaults)
        XCTAssertEqual(reloaded.notchIslandForm, .pill)
        XCTAssertEqual(reloaded.notchIslandHeightMode, .custom)
        XCTAssertEqual(reloaded.notchIslandCustomHeight, 30)
        XCTAssertEqual(reloaded.notchIslandHoverDelay, 0.6, accuracy: 0.0001)
        XCTAssertTrue(reloaded.notchIslandHidesUntilHover)
        XCTAssertTrue(reloaded.notchIslandHiddenFromCapture)

        model.notchIslandHeightMode = .menuBar
        XCTAssertEqual(model.notchIslandOptions.height, nil, "back to the menu bar")
        XCTAssertEqual(Preferences.load(from: scratch.defaults).notchIslandCustomHeight, 30, "the custom height is kept for next time")
    }

    func testOutOfRangeAndCorruptValuesAreClampedOrIgnored() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let model = PreferencesModel(defaults: scratch.defaults)
        model.notchIslandCustomHeight = 400
        XCTAssertEqual(model.notchIslandCustomHeight, 44, "clamped on write")
        model.notchIslandHoverDelay = -3
        XCTAssertEqual(model.notchIslandHoverDelay, 0)
        model.notchIslandHoverDelay = .nan
        XCTAssertEqual(model.notchIslandHoverDelay, NotchIslandInteraction.defaultDwellSeconds, "a non-number is the default")

        scratch.defaults.set("hexagon", forKey: Preferences.Keys.notchIslandForm)
        scratch.defaults.set("tall", forKey: Preferences.Keys.notchIslandHeightMode)
        scratch.defaults.set(2.0, forKey: Preferences.Keys.notchIslandCustomHeight)
        scratch.defaults.set(9.0, forKey: Preferences.Keys.notchIslandHoverDelay)
        let loaded = Preferences.load(from: scratch.defaults)
        XCTAssertEqual(loaded.notchIslandForm, .notch)
        XCTAssertEqual(loaded.notchIslandHeightMode, .menuBar)
        XCTAssertEqual(loaded.notchIslandCustomHeight, 20, "clamped on load")
        XCTAssertEqual(loaded.notchIslandHoverDelay, 1)
        scratch.defaults.set("soon", forKey: Preferences.Keys.notchIslandHoverDelay)
        XCTAssertEqual(Preferences.load(from: scratch.defaults).notchIslandHoverDelay, NotchIslandInteraction.defaultDwellSeconds, "not a number: ignored")
    }

    func testDiscoveryHidesTheStatusItemOnce() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let model = PreferencesModel(defaults: scratch.defaults)
        XCTAssertTrue(model.markNotchIslandDiscovered())
        XCTAssertTrue(model.notchIslandDiscovered)
        XCTAssertFalse(model.statusItemVisible)
        model.statusItemVisible = true
        XCTAssertFalse(model.markNotchIslandDiscovered(), "only the first time")
        XCTAssertTrue(model.statusItemVisible, "a later hand-set icon is left alone")
    }

    func testAppearanceDefaultsToDarkOnTheMacOnly() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let fresh = Preferences.load(from: scratch.defaults)
        #if os(macOS)
        XCTAssertEqual(fresh.appearance, .dark)
        #else
        XCTAssertEqual(fresh.appearance, .system)
        #endif
        scratch.defaults.set(AppearanceMode.light.rawValue, forKey: Preferences.Keys.appearance)
        XCTAssertEqual(Preferences.load(from: scratch.defaults).appearance, .light, "a chosen theme is kept")
    }
}
