import XCTest
import UsageKit
@testable import AIMeter

/// `NotificationPreferences`' per-window toggles must be scoped by
/// provider — the concrete bug this guards against: two providers both
/// reporting `.session` sharing the exact same stored toggle.
@MainActor
final class NotificationPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "AIMeterTests.NotificationPreferences"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testPerWindowToggleIsScopedByProvider() {
        let prefs = NotificationPreferences(defaults: defaults)

        prefs.setEnabled(true, for: "claude", kind: .session)

        XCTAssertTrue(prefs.isEnabled(for: "claude", kind: .session))
        XCTAssertFalse(prefs.isEnabled(for: "openai", kind: .session))
    }

    func testDifferentKindsUnderSameProviderAreIndependent() {
        let prefs = NotificationPreferences(defaults: defaults)

        prefs.setEnabled(true, for: "claude", kind: .session)

        XCTAssertTrue(prefs.isEnabled(for: "claude", kind: .session))
        XCTAssertFalse(prefs.isEnabled(for: "claude", kind: .weekly))
    }

    func testModelSpecificKindIsScopedByProviderToo() {
        let prefs = NotificationPreferences(defaults: defaults)

        prefs.setEnabled(true, for: "claude", kind: .modelSpecific("Fable"))

        XCTAssertTrue(prefs.isEnabled(for: "claude", kind: .modelSpecific("Fable")))
        XCTAssertFalse(prefs.isEnabled(for: "openai", kind: .modelSpecific("Fable")))
    }

    func testDisablingOneProviderDoesNotAffectAnother() {
        let prefs = NotificationPreferences(defaults: defaults)
        prefs.setEnabled(true, for: "claude", kind: .session)
        prefs.setEnabled(true, for: "openai", kind: .session)

        prefs.setEnabled(false, for: "claude", kind: .session)

        XCTAssertFalse(prefs.isEnabled(for: "claude", kind: .session))
        XCTAssertTrue(prefs.isEnabled(for: "openai", kind: .session))
    }

    // MARK: - Global smart toggles (intentionally unscoped)

    func testGlobalTogglesAreOneSettingAcrossEverything() {
        // Run-out / near-limit / early-reset / limit-reached are one
        // setting across every provider and window, not a per-window
        // concept — unlike the reset toggle above, there's nothing to scope.
        let prefs = NotificationPreferences(defaults: defaults)
        prefs.runOutWarningsEnabled = true
        prefs.nearLimitThreshold = 70

        XCTAssertTrue(prefs.runOutWarningsEnabled)
        XCTAssertEqual(prefs.nearLimitThreshold, 70)
    }

    func testNearLimitThresholdIsClamped() {
        let prefs = NotificationPreferences(defaults: defaults)

        prefs.nearLimitThreshold = 10
        XCTAssertEqual(prefs.nearLimitThreshold, 50) // clamped to the floor

        prefs.nearLimitThreshold = 99
        XCTAssertEqual(prefs.nearLimitThreshold, 95) // clamped to the ceiling
    }
}
