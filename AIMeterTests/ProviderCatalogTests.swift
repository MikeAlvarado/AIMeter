import XCTest
import UsageKit
@testable import AIMeter

final class ProviderCatalogTests: XCTestCase {
    func testKnownProviderName() {
        XCTAssertEqual(ProviderCatalog.displayName(for: ClaudeProvider.providerID), ClaudeProvider.providerDisplayName)
        XCTAssertEqual(ProviderCatalog.defaultProviderID, ClaudeProvider.providerID)
    }

    func testLegacyAccountIsTheMigratedSentinel() {
        let legacy = ProviderCatalog.legacyAccount
        XCTAssertEqual(legacy.accountID, ClaudeKeychainCredentialSource.legacyAccountID)
        XCTAssertEqual(legacy.providerID, ClaudeProvider.providerID)
        XCTAssertEqual(legacy.credentialStrategy, .managed)
    }

    func testMakeProviderBuildsTheClaudeProvider() {
        let keychain = KeychainStore(service: "aimeter.tests")
        let bundle = ProviderCatalog.makeProvider(for: .managed("x", name: "X"), keychain: keychain)
        XCTAssertTrue(bundle.provider is ClaudeProvider)
        XCTAssertTrue(bundle.credentials is ClaudeKeychainCredentialSource)
        XCTAssertEqual(bundle.provider.id, ClaudeProvider.providerID)
    }

    #if os(macOS)
    func testAutoDetectedAccountGetsTheCLIMirror() {
        let keychain = KeychainStore(service: "aimeter.tests")
        var account = ConnectedAccount.managed("claude", name: "Claude")
        account.credentialStrategy = .autoDetected
        let bundle = ProviderCatalog.makeProvider(for: account, keychain: keychain)
        XCTAssertTrue(bundle.credentials is ClaudeAutoCredentialSource)
    }
    #endif
}
