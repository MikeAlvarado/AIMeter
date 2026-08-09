import XCTest
@testable import UsageKit

final class ClaudeKeychainCredentialSourceTests: XCTestCase {
    func testLegacyClaudeAccountResolvesToDefaultKey() {
        XCTAssertEqual(
            ClaudeKeychainCredentialSource.storageKey(for: "claude"),
            ClaudeKeychainCredentialSource.defaultKey
        )
    }

    func testOtherAccountsResolveToASuffixedKey() {
        XCTAssertEqual(
            ClaudeKeychainCredentialSource.storageKey(for: "work-uuid"),
            "claude.credentials.work-uuid"
        )
    }
}
