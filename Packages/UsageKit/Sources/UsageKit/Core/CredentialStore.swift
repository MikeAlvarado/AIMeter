import Foundation

/// What the app needs from any provider's credential storage, whatever the
/// credential type: a way to remove it on disconnect and a way to drop an
/// in-memory copy. Provider-specific sources (`ClaudeCredentialSource`)
/// refine this with their own typed `load`/`save`; the app's
/// `RefreshService` holds only this, so disconnecting never has to know
/// which provider it's disconnecting.
public protocol CredentialStore: Sendable {
    /// Removes the stored credentials for this account.
    func clear() throws
    /// Drops any in-memory copy this source keeps, so the next load reads
    /// the backing store again. `ClaudeProvider` calls it when the endpoint
    /// rejects a token from a source that can't refresh it — the one case
    /// where a cached copy can outlive the login it mirrors (the CLI logged
    /// out or switched accounts). A no-op for sources that don't cache.
    func invalidateCache()
}

public extension CredentialStore {
    func invalidateCache() {}
}
