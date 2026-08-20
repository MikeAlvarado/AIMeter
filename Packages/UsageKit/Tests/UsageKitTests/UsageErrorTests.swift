import XCTest
@testable import UsageKit

final class UsageErrorTests: XCTestCase {
    /// The three credential failures no retry can fix — the UI offers a
    /// "sign in again" affordance for these instead of a dead-end message.
    func testCredentialFailuresRequireReauthentication() {
        XCTAssertTrue(UsageError.notAuthenticated.requiresReauthentication)
        XCTAssertTrue(UsageError.tokenExpired.requiresReauthentication)
        XCTAssertTrue(UsageError.credentialsNotFound("none stored").requiresReauthentication)
    }

    /// Everything else is transient or unrelated to the credentials, so it
    /// keeps rendering as a plain error — signing in again wouldn't help.
    func testTransientFailuresDoNotRequireReauthentication() {
        XCTAssertFalse(UsageError.rateLimited(retryAfter: 30, body: nil).requiresReauthentication)
        XCTAssertFalse(UsageError.httpError(statusCode: 503, body: nil).requiresReauthentication)
        XCTAssertFalse(UsageError.invalidResponse("no usage windows").requiresReauthentication)
        XCTAssertFalse(UsageError.storage("keychain -34018").requiresReauthentication)
    }
}
