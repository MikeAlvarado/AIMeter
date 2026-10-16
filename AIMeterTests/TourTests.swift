import XCTest
import UsageKit
@testable import AIMeter

/// The tour (see `Tour`): who gets it, its steps, and which new features a
/// release still offers after an update.
final class TourTests: XCTestCase {
    func testTheFullTourIsForAFreshInstallOnly() {
        XCTAssertTrue(Tour.isDue(completed: false, hasPriorInstall: false))
        XCTAssertFalse(Tour.isDue(completed: true, hasPriorInstall: false), "finished or skipped")
        XCTAssertFalse(Tour.isDue(completed: false, hasPriorInstall: true), "an upgrade gets the new features' cards instead")
    }

    func testTheStepsWelcomeFirstAndConnectLast() {
        let steps = Tour.steps
        XCTAssertEqual(steps.first, .welcome)
        XCTAssertEqual(steps.last, .connect)
        XCTAssertEqual(Set(steps).count, steps.count, "no step twice")
        for step in steps where step.canBeTurnedOn {
            XCTAssertNotNil(TourActions.title(for: step), "a step that can be turned on has its button: \(step.rawValue)")
        }
        #if os(macOS)
        XCTAssertFalse(steps.contains(.widgets), "the Mac's widgets need no walk-through")
        #else
        XCTAssertEqual(steps, [.welcome, .widgets, .alerts, .connect])
        #endif
    }

    private let release = WhatsNew.Release(version: "2.1.0", items: [
        WhatsNewTests.item("pawprint.fill", feature: "sessions"),
        WhatsNewTests.item("rectangle.split.3x1", feature: "notchIsland"),
        WhatsNewTests.item("paintpalette", feature: "colors"),
        WhatsNewTests.item("chart.xyaxis.line"),
        WhatsNewTests.item("sparkles", feature: "somethingFromTheFuture"),
    ])

    func testAnUpdateOffersWhatIsOffAndWasNeverOffered() throws {
        let offers = try XCTUnwrap(Tour.pendingOffers(in: release, offered: [], canOffer: { _ in true }))
        XCTAssertEqual(offers.version, "2.1.0")
        XCTAssertEqual(offers.items.map(\.symbol), ["pawprint.fill", "rectangle.split.3x1"],
                       "the colors only explain; a note without a feature, or with one this version doesn't know, offers nothing")
        let afterOne = try XCTUnwrap(Tour.pendingOffers(in: release, offered: [.sessions], canOffer: { _ in true }))
        XCTAssertEqual(afterOne.items.map(\.symbol), ["rectangle.split.3x1"], "offered once is enough")
        XCTAssertNil(Tour.pendingOffers(in: release, offered: [], canOffer: { $0 != .sessions && $0 != .notchIsland }),
                     "on already, or not for this Mac")
        XCTAssertNil(Tour.pendingOffers(in: nil, offered: [], canOffer: { _ in true }))
    }

    #if os(macOS)
    /// The session's name with the menu bar clearance is on once both
    /// switches are, the way a login item waiting for approval is: what may
    /// be left is macOS's permission, which the label says how to give,
    /// never a button that would prompt again.
    func testTheSessionNamesAreOnWithBothSwitches() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let prefs = PreferencesModel(defaults: scratch.defaults)
        let model = UsageModel(registry: AccountRegistryStore(userDefaults: scratch.defaults), platformServices: false)
        prefs.claudeSessionsShowsName = true
        XCTAssertFalse(TourActions.isActive(.sessionNames, model: model, prefs: prefs, notificationsAllowed: false))
        prefs.claudeSessionsAvoidsMenus = true
        XCTAssertTrue(TourActions.isActive(.sessionNames, model: model, prefs: prefs, notificationsAllowed: false))
    }
    #endif

    func testANoteNamesItsFeatureByRawValue() throws {
        let json = #"""
        {"releases": [{"version": "2.1.0", "items": [
            {"symbol": "a", "title": {"en": "A"}, "detail": {"en": "A"}, "feature": "notchIsland"},
            {"symbol": "b", "title": {"en": "B"}, "detail": {"en": "B"}}
        ]}]}
        """#
        let notes = try JSONDecoder().decode(WhatsNew.self, from: Data(json.utf8))
        XCTAssertEqual(notes.releases[0].items.map(\.tourFeature), [.notchIsland, nil])
    }
}
