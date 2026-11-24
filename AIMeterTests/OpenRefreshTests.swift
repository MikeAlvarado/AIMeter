import XCTest
import UsageKit
@testable import AIMeter

/// Opening the island or the popover refreshes, at most every 15 s. Only
/// the rule and the cases that refresh nothing are run here: a refresh
/// with a real account would fetch, which reads the Keychain.
final class OpenRefreshTests: XCTestCase {
    func testDueOnTheFirstOpenAndAgainAfterTheFloor() {
        let now = Date()
        XCTAssertTrue(UsageModel.isOpenRefreshDue(lastRefreshed: nil, now: now))
        XCTAssertFalse(UsageModel.isOpenRefreshDue(lastRefreshed: now, now: now))
        XCTAssertFalse(UsageModel.isOpenRefreshDue(lastRefreshed: now.addingTimeInterval(-14.9), now: now))
        XCTAssertTrue(UsageModel.isOpenRefreshDue(lastRefreshed: now.addingTimeInterval(-15), now: now))
        XCTAssertEqual(UsageModel.openRefreshMinimumInterval, 15)
    }

    @MainActor
    func testNothingConnectedRefreshesNothing() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let model = UsageModel(registry: AccountRegistryStore(userDefaults: scratch.defaults), platformServices: false)
        XCTAssertFalse(model.refreshOnOpen())
        XCTAssertNil(model.lastOpenRefresh)
    }

    @MainActor
    func testTheDemoRefreshesNothing() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let model = UsageModel(registry: AccountRegistryStore(userDefaults: scratch.defaults), platformServices: false)
        model.enterDemoMode()
        XCTAssertFalse(model.refreshOnOpen())
        XCTAssertNil(model.lastOpenRefresh)
    }
}
