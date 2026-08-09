import Foundation

/// Persists the latest `UsageSnapshot` per connected account in the App
/// Group, the only channel between app and widget extension. Widgets read
/// the last snapshot here; only the app (and its background task) writes.
///
/// Keyed by `accountID`, not `UsageSnapshot.providerID` — a snapshot's
/// `providerID` identifies the provider *family* ("claude") and stays the
/// same across every account of that provider, so it can't be used as the
/// storage key once more than one account exists. `accountID` (an
/// `AccountRegistryStore.ConnectedAccount`'s id) is the actual per-login
/// identity and is always supplied by the caller, which already knows
/// which account it's operating on.
public struct SnapshotStore: @unchecked Sendable {
    private let defaults: UserDefaults

    /// - Parameter suiteName: the App Group identifier,
    ///   e.g. "group.com.mikealvarado.aimeter". Returns nil if the suite
    ///   cannot be opened (missing entitlement).
    public init?(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return nil
        }
        self.defaults = defaults
    }

    public init(userDefaults: UserDefaults) {
        self.defaults = userDefaults
    }

    public func save(_ snapshot: UsageSnapshot, for accountID: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            throw UsageError.storage("snapshot encode failed: \(error.localizedDescription)")
        }
        defaults.set(data, forKey: Self.key(for: accountID))
    }

    public func snapshot(for accountID: String) -> UsageSnapshot? {
        guard let data = defaults.data(forKey: Self.key(for: accountID)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    public func removeSnapshot(for accountID: String) {
        defaults.removeObject(forKey: Self.key(for: accountID))
    }

    private static func key(for accountID: String) -> String {
        "usage.snapshot.\(accountID)"
    }
}
