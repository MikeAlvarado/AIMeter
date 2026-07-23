import Foundation

/// A bounded, reset-aware history of usage samples per window, in the App
/// Group — the extra data (beyond the single latest snapshot in
/// `SnapshotStore`) that the recent-rate run-out predictor needs. Written
/// wherever a fetch persists a snapshot (the app's refresh and the iOS
/// widget self-fetch); read by the app to project run-out and schedule
/// alerts.
public struct UsageHistoryStore: @unchecked Sendable {
    private let defaults: UserDefaults

    /// Per-kind sample cap; oldest are dropped past this.
    public static let maxSamplesPerKind = 64
    /// A used% fall of at least this many points between consecutive
    /// samples means the window reset — the prior samples belong to a spent
    /// window and are discarded so a rate never spans a reset boundary.
    public static let resetDropThreshold: Double = 10

    public init?(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = defaults
    }

    public init(userDefaults: UserDefaults) {
        self.defaults = userDefaults
    }

    /// Time-ordered samples for one window kind (oldest first).
    public func samples(for providerID: String, kind: UsageWindow.Kind) -> [UsageSample] {
        load(providerID)[kind.storageKey] ?? []
    }

    /// When history first started being recorded for this provider — set
    /// once on the first `record` and kept across window resets (unlike the
    /// samples themselves). Drives the pace warm-up: how long we've been
    /// observing the account. nil until the first fetch, cleared on disconnect.
    public func observingSince(for providerID: String) -> Date? {
        defaults.object(forKey: Self.sinceKey(for: providerID)) as? Date
    }

    /// Appends one sample per window in the snapshot. When a kind's used%
    /// fell (a reset), its prior samples are dropped first so the recorded
    /// series always lies within the current window.
    public func record(_ snapshot: UsageSnapshot, at now: Date = Date()) {
        if defaults.object(forKey: Self.sinceKey(for: snapshot.providerID)) == nil {
            defaults.set(now, forKey: Self.sinceKey(for: snapshot.providerID))
        }
        var byKind = load(snapshot.providerID)
        for window in snapshot.windows {
            let key = window.kind.storageKey
            var series = byKind[key] ?? []
            if let last = series.last, window.usedPct < last.usedPct - Self.resetDropThreshold {
                series = []
            }
            series.append(UsageSample(timestamp: now, usedPct: window.usedPct))
            if series.count > Self.maxSamplesPerKind {
                series.removeFirst(series.count - Self.maxSamplesPerKind)
            }
            byKind[key] = series
        }
        save(byKind, for: snapshot.providerID)
    }

    public func clear(for providerID: String) {
        defaults.removeObject(forKey: Self.key(for: providerID))
        defaults.removeObject(forKey: Self.sinceKey(for: providerID))
    }

    // MARK: - Persistence

    private func load(_ providerID: String) -> [String: [UsageSample]] {
        guard let data = defaults.data(forKey: Self.key(for: providerID)) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: [UsageSample]].self, from: data)) ?? [:]
    }

    private func save(_ byKind: [String: [UsageSample]], for providerID: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(byKind) else { return }
        defaults.set(data, forKey: Self.key(for: providerID))
    }

    private static func key(for providerID: String) -> String {
        "usage.history.\(providerID)"
    }

    private static func sinceKey(for providerID: String) -> String {
        "usage.history.since.\(providerID)"
    }
}
