import XCTest
import UsageKit
@testable import AIMeter

final class NotificationPreferencesTests: XCTestCase {
    private var scratch: ScratchDefaults!

    override func setUp() {
        scratch = ScratchDefaults()
    }

    override func tearDown() {
        scratch.wipe()
    }

    private func prefs(_ accountID: String) -> NotificationPreferences {
        NotificationPreferences(accountID: accountID, defaults: scratch.defaults)
    }

    func testEverySmartAlertIsOffByDefaultExceptSignIn() {
        let p = prefs("a")
        for alert in SmartAlert.allCases {
            XCTAssertEqual(p.isEnabled(alert), alert == .reauth, "\(alert)")
        }
    }

    func testSmartAlertTogglesRoundTripPerAccount() {
        let a = prefs("a"), b = prefs("b")
        a.setEnabled(true, .runOut)
        XCTAssertTrue(a.isEnabled(.runOut))
        XCTAssertFalse(b.isEnabled(.runOut), "another account's toggle is independent")
        a.setEnabled(false, .reauth)
        XCTAssertFalse(a.isEnabled(.reauth))
        XCTAssertTrue(b.isEnabled(.reauth), "the on-by-default family stays on elsewhere")
    }

    func testPerWindowResetTogglesAreKeyedByKind() {
        let p = prefs("a")
        p.setEnabled(true, for: .modelSpecific("Fable"))
        XCTAssertTrue(p.isEnabled(for: .modelSpecific("Fable")))
        XCTAssertFalse(p.isEnabled(for: .session))
    }

    func testNearLimitThresholdDefaultsAndClamps() {
        let p = prefs("a")
        XCTAssertEqual(p.nearLimitThreshold, 80)
        p.nearLimitThreshold = 10
        XCTAssertEqual(p.nearLimitThreshold, 50)
        p.nearLimitThreshold = 99
        XCTAssertEqual(p.nearLimitThreshold, 95)
    }

    func testClearRemovesOnlyThisAccountsKeys() {
        let a = prefs("a"), b = prefs("b")
        a.setEnabled(true, .nearLimit)
        a.setEnabled(true, for: .session)
        a.reauthAlertDelivered = true
        b.setEnabled(true, .nearLimit)
        a.peakEnabled = true

        a.clear()

        XCTAssertFalse(a.isEnabled(.nearLimit))
        XCTAssertFalse(a.isEnabled(for: .session))
        XCTAssertFalse(a.reauthAlertDelivered)
        XCTAssertTrue(a.isEnabled(.reauth), "back to the default, not forced off")
        XCTAssertTrue(b.isEnabled(.nearLimit), "the other account is untouched")
        XCTAssertTrue(b.peakEnabled, "the global peak toggle has no account suffix and survives")
    }
}
