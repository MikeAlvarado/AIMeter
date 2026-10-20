import Foundation

/// The app's own copy of a Codex login, from the in-app device-code
/// sign-in, in the app's Keychain (the shared access group on iOS, so
/// the widget can fetch with it). Refreshed in place.
public struct CodexKeychainCredentialSource: CodexCredentialSource {
    /// The Keychain key for an account: every Codex account gets its own
    /// suffixed key (there is no legacy single-account install of this
    /// provider to keep a bare key for).
    public static func storageKey(for accountID: String) -> String {
        "codex.credentials.\(accountID)"
    }

    public var allowsRefresh: Bool { true }

    private let store: KeychainStore
    private let key: String

    public init(store: KeychainStore, key: String) {
        self.store = store
        self.key = key
    }

    public func load() async throws -> CodexCredentials {
        guard let credentials = try store.value(CodexCredentials.self, for: key) else {
            throw UsageError.credentialsNotFound("no Codex token stored yet")
        }
        return credentials
    }

    public func save(_ credentials: CodexCredentials) async throws {
        try store.set(credentials, for: key)
    }

    public func clear() throws {
        try store.delete(key)
    }
}

#if os(macOS)
/// Read-only mirror of the login the Codex CLI keeps on this Mac
/// (`$CODEX_HOME/auth.json`, else `~/.codex/auth.json`), the Codex
/// counterpart of `ClaudeCodeLocalCredentialSource`: zero setup, never
/// written to, never refreshed (the CLI rotates its own pair when it
/// runs; a token this source finds expired is reported as
/// `tokenExpired`, which the UI answers with "Sign in again"). A login
/// the CLI keeps in the keyring instead of the file is not found.
public struct CodexFileCredentialSource: CodexCredentialSource {
    public var allowsRefresh: Bool { false }

    public init() {}

    /// Where the CLI's file is, whether or not it exists.
    public static var authFileURL: URL {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        return home.appendingPathComponent("auth.json", isDirectory: false)
    }

    /// Whether the CLI has a login here to mirror (the file exists and
    /// holds tokens), for the Connect sheet's one-click option.
    public static var isAvailable: Bool {
        guard let data = try? Data(contentsOf: authFileURL) else { return false }
        return (try? CodexCredentials.fromAuthJSON(data)) != nil
    }

    public func load() async throws -> CodexCredentials {
        guard let data = try? Data(contentsOf: Self.authFileURL) else {
            throw UsageError.credentialsNotFound(
                "Codex login not found (\(Self.authFileURL.path)). Install Codex and run `codex login`, or sign in through AIMeter."
            )
        }
        return try .fromAuthJSON(data)
    }

    public func save(_ credentials: CodexCredentials) async throws {
        // Read-only: never touch the CLI's file.
    }

    public func clear() throws {
        // Same: disconnecting AIMeter must never log the CLI out.
    }
}
#endif
