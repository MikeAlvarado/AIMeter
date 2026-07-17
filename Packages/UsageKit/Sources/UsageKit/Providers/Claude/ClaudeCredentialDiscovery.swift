import Foundation
#if os(macOS)
import Security

/// Read-only credential source that reuses what Claude Code already
/// maintains on this Mac, so the user never pastes a token. Reads the
/// Keychain item first, then falls back to ~/.claude/.credentials.json.
///
/// `allowsRefresh` is false by design: Claude Code refreshes its own token
/// (rotating the refresh token in the process), so we always re-read on
/// fetch instead of competing for the refresh cycle.
public struct ClaudeCodeLocalCredentialSource: ClaudeCredentialSource {
    public static let keychainService = "Claude Code-credentials"

    public var allowsRefresh: Bool { false }

    public init() {}

    public func load() async throws -> ClaudeCredentials {
        if let data = Self.readClaudeCodeKeychainItem() {
            return try .fromClaudeCodeJSON(data)
        }
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: fileURL) {
            return try .fromClaudeCodeJSON(data)
        }
        throw UsageError.credentialsNotFound(
            "Claude Code login not found (Keychain item \"\(Self.keychainService)\" or ~/.claude/.credentials.json). Install Claude Code and log in, or paste a token manually."
        )
    }

    public func save(_ credentials: ClaudeCredentials) async throws {
        // Read-only: never mutate Claude Code's credentials.
    }

    private static func readClaudeCodeKeychainItem() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }
}
#endif
