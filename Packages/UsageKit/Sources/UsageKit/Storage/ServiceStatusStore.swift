import Foundation

/// The last fetched `ServiceStatus` per provider family, in the App Group —
/// so the menu bar popover and the dashboard can show the last known
/// state before the first check of a launch completes, and so a widget
/// could read it one day. Keyed by `providerID`: status is a property of
/// the service, not of any one account.
public struct ServiceStatusStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init?(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = defaults
    }

    public init(userDefaults: UserDefaults) {
        self.defaults = userDefaults
    }

    public func status(for providerID: String) -> ServiceStatus? {
        guard let data = defaults.data(forKey: Self.key(for: providerID)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ServiceStatus.self, from: data)
    }

    public func save(_ status: ServiceStatus, for providerID: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(status) else { return }
        defaults.set(data, forKey: Self.key(for: providerID))
    }

    public func clear(for providerID: String) {
        defaults.removeObject(forKey: Self.key(for: providerID))
    }

    private static func key(for providerID: String) -> String {
        "service.status.\(providerID)"
    }
}
