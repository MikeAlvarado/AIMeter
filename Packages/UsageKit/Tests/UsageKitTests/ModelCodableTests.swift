import XCTest
@testable import UsageKit

final class ModelCodableTests: XCTestCase {
    func testWindowKindRoundtrip() throws {
        let kinds: [UsageWindow.Kind] = [.session, .weekly, .modelSpecific("Fable")]
        for kind in kinds {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(UsageWindow.Kind.self, from: data)
            XCTAssertEqual(decoded, kind)
        }
    }

    func testSnapshotRoundtrip() throws {
        let snapshot = UsageSnapshot(
            providerID: "claude",
            planName: "max",
            fetchedAt: Date(timeIntervalSince1970: 1_780_000_000),
            windows: [
                UsageWindow(kind: .session, usedPct: 24, resetsAt: Date(), severity: .normal, isActive: true),
                UsageWindow(kind: .modelSpecific("Fable"), usedPct: 5),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(UsageSnapshot.self, from: try encoder.encode(snapshot))

        XCTAssertEqual(decoded.providerID, "claude")
        XCTAssertEqual(decoded.windows.count, 2)
        XCTAssertEqual(decoded.sessionWindow?.usedPct, 24)
        XCTAssertEqual(decoded.modelWindows.first?.kind, .modelSpecific("Fable"))
    }

    func testClaudeCodeCredentialsParsing() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "at",
            "refreshToken": "rt",
            "expiresAt": 1789600295000,
            "scopes": ["user:profile", "user:inference"],
            "subscriptionType": "pro"
          }
        }
        """
        let credentials = try ClaudeCredentials.fromClaudeCodeJSON(Data(json.utf8))

        XCTAssertEqual(credentials.accessToken, "at")
        XCTAssertEqual(credentials.refreshToken, "rt")
        XCTAssertEqual(credentials.expiresAt, Date(timeIntervalSince1970: 1_789_600_295))
        XCTAssertEqual(credentials.scopes, ["user:profile", "user:inference"])
        XCTAssertEqual(credentials.subscriptionType, "pro")
        XCTAssertFalse(credentials.isExpired)
    }

    func testBareOAuthObjectAlsoParses() throws {
        let json = """
        {"accessToken": "at", "expiresAt": 1000, "subscriptionType": "max"}
        """
        let credentials = try ClaudeCredentials.fromClaudeCodeJSON(Data(json.utf8))
        XCTAssertEqual(credentials.accessToken, "at")
        XCTAssertTrue(credentials.isExpired)
    }

    func testGarbageCredentialsThrow() {
        XCTAssertThrowsError(try ClaudeCredentials.fromClaudeCodeJSON(Data("not json".utf8)))
    }
}
