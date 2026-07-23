import XCTest
import UsageKit
@testable import AIMeter

/// `RefreshService.migrateNotificationKeysToProviderScope` is the one-time
/// rewrite that keeps existing users' notification toggles working after
/// the provider-scoped key format shipped — any bug here silently resets
/// real users' preferences to off on upgrade, so it's worth covering
/// directly rather than trusting manual QA alone.
@MainActor
final class NotificationKeyMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "AIMeterTests.NotificationMigration"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLegacyKeyIsRewrittenToClaudeScopedKey() {
        defaults.set(true, forKey: "notify.session")

        RefreshService.migrateNotificationKeysToProviderScope(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: "notify.claude.session"))
    }

    func testModelSpecificKeyRoundTrips() {
        defaults.set(true, forKey: "notify.model.Fable")

        RefreshService.migrateNotificationKeysToProviderScope(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: "notify.claude.model.Fable"))
    }

    func testDisabledLegacyKeyStillMigratesAsAnExplicitKey() {
        // UserDefaults distinguishes "never set" from "explicitly false" —
        // the migration must copy the key itself, not just truthy values,
        // otherwise a user who turned a toggle off would silently look
        // identical to one who never touched it.
        defaults.set(false, forKey: "notify.weekly")

        RefreshService.migrateNotificationKeysToProviderScope(defaults: defaults)

        XCTAssertNotNil(defaults.object(forKey: "notify.claude.weekly"))
        XCTAssertFalse(defaults.bool(forKey: "notify.claude.weekly"))
    }

    func testGlobalSmartTogglesAreNotRewritten() {
        // Not per-window keys — must survive untouched, no "claude." rewrite.
        defaults.set(true, forKey: "notify.runout")
        defaults.set(42.0, forKey: "notify.nearLimitThreshold")

        RefreshService.migrateNotificationKeysToProviderScope(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: "notify.runout"))
        XCTAssertEqual(defaults.double(forKey: "notify.nearLimitThreshold"), 42.0)
        XCTAssertNil(defaults.object(forKey: "notify.claude.runout"))
    }

    func testAlreadyScopedKeysAreLeftAlone() {
        defaults.set(false, forKey: "notify.claude.session")

        RefreshService.migrateNotificationKeysToProviderScope(defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: "notify.claude.session"))
    }

    func testMigrationIsIdempotent() {
        defaults.set(true, forKey: "notify.session")
        RefreshService.migrateNotificationKeysToProviderScope(defaults: defaults)

        // A legacy-shaped key appearing after the flag is already set
        // (shouldn't happen in practice, but proves the guard works) must
        // not be picked up by a second call.
        defaults.set(true, forKey: "notify.weekly")
        RefreshService.migrateNotificationKeysToProviderScope(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "notify.claude.weekly"))
    }
}
