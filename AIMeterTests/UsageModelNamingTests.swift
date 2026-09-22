import XCTest
import UsageKit
@testable import AIMeter

/// `UsageModel` against a scratch registry: naming and ordering, the
/// parts of the model that never touch the network. `platformServices:
/// false` skips migration (it probes the real Keychain), the macOS
/// scheduler, and the notification sweep.
final class UsageModelNamingTests: XCTestCase {
    private var scratch: ScratchDefaults!
    private var registry: AccountRegistryStore!

    override func setUp() {
        scratch = ScratchDefaults()
        registry = AccountRegistryStore(userDefaults: scratch.defaults)
        registry.add(.managed("acc-work", name: "Work"))
        registry.add(.managed("acc-home", name: "Home"))
    }

    override func tearDown() {
        scratch.wipe()
    }

    private func makeModel() -> UsageModel {
        UsageModel(registry: registry, platformServices: false)
    }

    func testLoadsAccountsInRegistryOrder() {
        let model = makeModel()
        XCTAssertEqual(model.accounts.map(\.account.displayName), ["Work", "Home"])
        XCTAssertFalse(model.needsConnection)
    }

    func testNameTakenIsCaseInsensitiveAndTrimmed() {
        let model = makeModel()
        XCTAssertTrue(model.isNameTaken("work"))
        XCTAssertTrue(model.isNameTaken("  HOME "))
        XCTAssertFalse(model.isNameTaken("Work", excluding: "acc-work"), "an account's own name is not a collision")
        XCTAssertFalse(model.isNameTaken("Other"))
    }

    func testSuggestedNicknameSkipsTakenNames() {
        let model = makeModel()
        let provider = ProviderCatalog.displayName(for: ProviderCatalog.defaultProviderID)
        XCTAssertEqual(model.suggestedNickname(), "\(provider) 3")
        model.rename("acc-home", to: "\(provider) 3")
        XCTAssertEqual(model.suggestedNickname(), "\(provider) 4")
    }

    func testRenameRejectsEmptyAndDuplicateNames() {
        let model = makeModel()
        XCTAssertFalse(model.rename("acc-work", to: "   "))
        XCTAssertFalse(model.rename("acc-work", to: "home"))
        XCTAssertTrue(model.rename("acc-work", to: "Work"), "an unchanged name is not a rejection")
        XCTAssertEqual(registry.account(for: "acc-work")?.displayName, "Work")
    }

    func testRenamePersistsToTheRegistryAndTheService() {
        let model = makeModel()
        XCTAssertTrue(model.rename("acc-work", to: " Office "))
        XCTAssertEqual(model.usage(for: "acc-work")?.account.displayName, "Office")
        XCTAssertEqual(registry.account(for: "acc-work")?.displayName, "Office")
        XCTAssertEqual(model.services["acc-work"]?.account.displayName, "Office")
    }

    func testMoveByOffsetRewritesRegistryOrder() {
        let model = makeModel()
        model.moveAccount("acc-home", by: -1)
        XCTAssertEqual(model.accounts.map(\.id), ["acc-home", "acc-work"])
        XCTAssertEqual(registry.accounts().map(\.accountID), ["acc-home", "acc-work"])
        model.moveAccount("acc-home", by: -1)
        XCTAssertEqual(model.accounts.map(\.id), ["acc-home", "acc-work"], "already first: no-op")
    }

    func testMoveOntoTargetTakesItsPlace() {
        registry.add(.managed("acc-third", name: "Third"))
        let model = makeModel()
        XCTAssertTrue(model.moveAccount("acc-third", onto: "acc-work"))
        XCTAssertEqual(model.accounts.map(\.id), ["acc-third", "acc-work", "acc-home"])
        XCTAssertFalse(model.moveAccount("acc-third", onto: "acc-third"))
    }

    func testPrimaryAccountFallsBackToTheFirst() {
        let model = makeModel()
        XCTAssertEqual(model.primaryAccountUsage(preferredID: "acc-home")?.id, "acc-home")
        XCTAssertEqual(model.primaryAccountUsage(preferredID: "gone")?.id, "acc-work")
        XCTAssertEqual(model.primaryAccountUsage(preferredID: nil)?.id, "acc-work")
    }

    func testDemoModeSwapsInTheNeutralAccount() {
        let model = makeModel()
        model.enterDemoMode()
        XCTAssertTrue(model.isDemoMode)
        XCTAssertEqual(model.accounts.map(\.account.displayName), ["Personal"])
        // Demo ignores renames silently (the UI hides the affordance) — not
        // a rejection, so the alert never re-presents, but nothing changes.
        model.rename("demo", to: "X")
        XCTAssertEqual(model.accounts.first?.account.displayName, "Personal")
        model.exitDemoMode()
        XCTAssertEqual(model.accounts.map(\.id), ["acc-work", "acc-home"])
    }
}
