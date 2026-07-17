import XCTest
@testable import UsageKit

final class ClaudeOAuthTests: XCTestCase {
    func testSessionBuildsAuthorizeURLWithPKCE() throws {
        let session = ClaudeOAuth.startSession()
        let components = try XCTUnwrap(
            URLComponents(url: session.authorizeURL, resolvingAgainstBaseURL: false)
        )
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        XCTAssertEqual(components.host, "claude.ai")
        XCTAssertEqual(components.path, "/oauth/authorize")
        XCTAssertEqual(items["code"], "true")
        XCTAssertEqual(items["client_id"], ClaudeOAuthClient.clientID)
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["redirect_uri"], "https://console.anthropic.com/oauth/code/callback")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["state"], session.state)
        XCTAssertFalse(session.codeVerifier.isEmpty)
        // Challenge must be base64url (no padding, no +/ characters).
        let challenge = try XCTUnwrap(items["code_challenge"])
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        // Fresh sessions must never reuse verifier/state.
        let other = ClaudeOAuth.startSession()
        XCTAssertNotEqual(other.codeVerifier, session.codeVerifier)
        XCTAssertNotEqual(other.state, session.state)
    }

    func testExchangeParsesCodeHashStateAndMapsCredentials() async throws {
        let transport = RecordingTransport(status: 200, body: """
        {"access_token": "sk-ant-oat01-abc", "refresh_token": "sk-ant-ort01-def",
         "expires_in": 28800, "scope": "user:profile user:inference"}
        """)
        let session = ClaudeOAuth.startSession()

        let credentials = try await ClaudeOAuth(transport: transport)
            .exchange(pastedCode: "  the-code#returned-state\n", session: session)

        XCTAssertEqual(credentials.accessToken, "sk-ant-oat01-abc")
        XCTAssertEqual(credentials.refreshToken, "sk-ant-ort01-def")
        XCTAssertEqual(credentials.scopes, ["user:profile", "user:inference"])
        let expiry = try XCTUnwrap(credentials.expiresAt)
        XCTAssertEqual(expiry.timeIntervalSinceNow, 28800, accuracy: 60)

        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let sent = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        XCTAssertEqual(sent["grant_type"], "authorization_code")
        XCTAssertEqual(sent["code"], "the-code")
        XCTAssertEqual(sent["state"], "returned-state")
        XCTAssertEqual(sent["code_verifier"], session.codeVerifier)
        XCTAssertEqual(sent["client_id"], ClaudeOAuthClient.clientID)
    }

    func testExchangeWithoutHashFallsBackToSessionState() async throws {
        let transport = RecordingTransport(status: 200, body: """
        {"access_token": "at"}
        """)
        let session = ClaudeOAuth.startSession()

        _ = try await ClaudeOAuth(transport: transport)
            .exchange(pastedCode: "bare-code", session: session)

        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(sent["code"], "bare-code")
        XCTAssertEqual(sent["state"], session.state)
    }

    func testRejectedCodeThrowsNotAuthenticated() async {
        let transport = RecordingTransport(status: 400, body: "{}")
        let session = ClaudeOAuth.startSession()

        do {
            _ = try await ClaudeOAuth(transport: transport)
                .exchange(pastedCode: "bad", session: session)
            XCTFail("expected notAuthenticated")
        } catch let error as UsageError {
            XCTAssertEqual(error, .notAuthenticated)
        } catch {
            XCTFail("expected UsageError, got \(error)")
        }
    }

    func testEmptyPasteThrows() async {
        let session = ClaudeOAuth.startSession()
        do {
            _ = try await ClaudeOAuth(transport: RecordingTransport(status: 200, body: "{}"))
                .exchange(pastedCode: "   ", session: session)
            XCTFail("expected invalidResponse")
        } catch let error as UsageError {
            guard case .invalidResponse = error else {
                return XCTFail("expected invalidResponse, got \(error)")
            }
        } catch {
            XCTFail("expected UsageError, got \(error)")
        }
    }
}

private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private(set) var lastRequest: URLRequest?
    private let status: Int
    private let body: String

    init(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}
