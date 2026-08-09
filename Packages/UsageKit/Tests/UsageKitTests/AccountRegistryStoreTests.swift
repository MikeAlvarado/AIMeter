import XCTest
@testable import UsageKit

final class AccountRegistryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "AccountRegistryStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func account(
        _ accountID: String,
        displayName: String = "Claude",
        strategy: ConnectedAccount.CredentialStrategy = .managed
    ) -> ConnectedAccount {
        ConnectedAccount(
            accountID: accountID,
            providerID: "claude",
            displayName: displayName,
            credentialStrategy: strategy,
            connectedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func testEmptyRegistryReturnsNoAccounts() {
        let store = AccountRegistryStore(userDefaults: defaults)
        XCTAssertEqual(store.accounts(), [])
        XCTAssertNil(store.account(for: "claude"))
    }

    func testAddAppendsInOrder() {
        let store = AccountRegistryStore(userDefaults: defaults)
        XCTAssertTrue(store.add(account("claude", displayName: "Personal")))
        XCTAssertTrue(store.add(account("work-uuid", displayName: "Work")))

        XCTAssertEqual(store.accounts().map(\.accountID), ["claude", "work-uuid"])
        XCTAssertEqual(store.account(for: "work-uuid")?.displayName, "Work")
    }

    func testAddingDuplicateAccountIDIsANoOp() {
        let store = AccountRegistryStore(userDefaults: defaults)
        XCTAssertTrue(store.add(account("claude", displayName: "First")))
        XCTAssertFalse(store.add(account("claude", displayName: "Second")))

        XCTAssertEqual(store.accounts().count, 1)
        XCTAssertEqual(store.account(for: "claude")?.displayName, "First")
    }

    func testRenameUpdatesDisplayNameOnly() {
        let store = AccountRegistryStore(userDefaults: defaults)
        store.add(account("claude", displayName: "Claude"))

        store.rename("claude", to: "Personal")

        let renamed = store.account(for: "claude")
        XCTAssertEqual(renamed?.displayName, "Personal")
        XCTAssertEqual(renamed?.accountID, "claude")
    }

    func testRenameMissingAccountIsANoOp() {
        let store = AccountRegistryStore(userDefaults: defaults)
        store.rename("claude", to: "Personal")
        XCTAssertEqual(store.accounts(), [])
    }

    func testRemoveDropsOnlyThatAccount() {
        let store = AccountRegistryStore(userDefaults: defaults)
        store.add(account("claude"))
        store.add(account("work-uuid", displayName: "Work"))

        store.remove("claude")

        XCTAssertEqual(store.accounts().map(\.accountID), ["work-uuid"])
    }

    func testReplaceAllOverwritesTheWholeList() {
        let store = AccountRegistryStore(userDefaults: defaults)
        store.add(account("claude"))

        store.replaceAll([account("a", displayName: "A"), account("b", displayName: "B")])

        XCTAssertEqual(store.accounts().map(\.accountID), ["a", "b"])
    }

    func testCredentialStrategyRoundtripsThroughCodable() {
        let store = AccountRegistryStore(userDefaults: defaults)
        store.add(account("claude", strategy: .autoDetected))
        store.add(account("work-uuid", strategy: .managed))

        XCTAssertEqual(store.account(for: "claude")?.credentialStrategy, .autoDetected)
        XCTAssertEqual(store.account(for: "work-uuid")?.credentialStrategy, .managed)
    }
}
