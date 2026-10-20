import XCTest
import UsageKit
@testable import AIMeter

/// Discreet mode: its keys, which accounts the Mac's glance surfaces
/// keep while it is on, and the primary they fall back to.
@MainActor
final class DiscreetModeTests: XCTestCase {
    private var scratch: ScratchDefaults!

    override func setUp() {
        super.setUp()
        scratch = ScratchDefaults()
    }

    override func tearDown() {
        scratch.wipe()
        super.tearDown()
    }

    private func makeModel() -> (UsageModel, PreferencesModel) {
        let registry = AccountRegistryStore(userDefaults: scratch.defaults)
        registry.add(.managed("personal", name: "Personal"))
        registry.add(.managed("work", name: "Work"))
        return (UsageModel(registry: registry, platformServices: false), PreferencesModel(defaults: scratch.defaults))
    }

    func testOffByDefaultAndTheMarksRoundTrip() {
        let prefs = PreferencesModel(defaults: scratch.defaults)
        XCTAssertFalse(prefs.discreetMode)
        XCTAssertTrue(prefs.discreetAccountIDs.isEmpty)
        prefs.setDiscreet(true, accountID: "personal")
        prefs.setDiscreet(true, accountID: "work")
        prefs.setDiscreet(false, accountID: "work")
        prefs.discreetMode = true
        let loaded = Preferences.load(from: scratch.defaults)
        XCTAssertTrue(loaded.discreetMode)
        XCTAssertEqual(loaded.discreetAccountIDs, ["personal"])
    }

    func testTheGlanceSurfacesLoseOnlyTheMarkedAccountsWhileItIsOn() {
        let (model, prefs) = makeModel()
        prefs.setDiscreet(true, accountID: "personal")
        XCTAssertEqual(model.glanceAccounts(prefs).map(\.id), ["personal", "work"], "off: everything")
        prefs.discreetMode = true
        XCTAssertEqual(model.glanceAccounts(prefs).map(\.id), ["work"])
        XCTAssertEqual(model.accounts.map(\.id), ["personal", "work"], "the Dashboard keeps everything")
    }

    func testThePrimaryFallsBackToTheFirstShownAndComesBack() {
        let (model, prefs) = makeModel()
        prefs.primaryAccountID = "personal"
        prefs.setDiscreet(true, accountID: "personal")
        XCTAssertEqual(model.glancePrimary(prefs)?.id, "personal")
        prefs.discreetMode = true
        XCTAssertEqual(model.glancePrimary(prefs)?.id, "work")
        XCTAssertEqual(prefs.primaryAccountID, "personal", "the choice is kept for when the mode goes off")
        prefs.setDiscreet(true, accountID: "work")
        XCTAssertNil(model.glancePrimary(prefs), "every account hidden: nothing to show")
        prefs.discreetMode = false
        XCTAssertEqual(model.glancePrimary(prefs)?.id, "personal")
    }
}
