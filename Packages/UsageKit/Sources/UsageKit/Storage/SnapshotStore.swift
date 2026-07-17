import Foundation

/// Persists the latest `UsageSnapshot` per provider in the App Group, the
/// only channel between app and widget extension. Widgets read the last
/// snapshot here; only the app (and its background task) writes.
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

    public func save(_ snapshot: UsageSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            throw UsageError.storage("snapshot encode failed: \(error.localizedDescription)")
        }
        defaults.set(data, forKey: Self.key(for: snapshot.providerID))
    }

    public func snapshot(for providerID: String) -> UsageSnapshot? {
        guard let data = defaults.data(forKey: Self.key(for: providerID)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    public func removeSnapshot(for providerID: String) {
        defaults.removeObject(forKey: Self.key(for: providerID))
    }

    private static func key(for providerID: String) -> String {
        "usage.snapshot.\(providerID)"
    }
}
