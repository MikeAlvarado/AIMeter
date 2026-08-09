import Foundation

/// A bounded, reset-aware history of usage samples per window, in the App
/// Group — the extra data (beyond the single latest snapshot in
/// `SnapshotStore`) that the recent-rate run-out predictor needs. Written
/// wherever a fetch persists a snapshot (the app's refresh and the iOS
/// widget self-fetch); read by the app to project run-out and schedule
/// alerts.
///
/// Keyed by `accountID`, same reasoning as `SnapshotStore`: a snapshot's
/// `providerID` is shared across every account of that provider, so
/// `record`/`samples`/etc. take the account's id explicitly rather than
/// reading it off the snapshot.
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
    public func samples(for accountID: String, kind: UsageWindow.Kind) -> [UsageSample] {
        load(accountID)[kind.storageKey] ?? []
    }

    /// When history first started being recorded for this account — set
    /// once on the first `record` and kept across window resets (unlike the
    /// samples themselves). Drives the pace warm-up: how long we've been
    /// observing the account. nil until the first fetch, cleared on disconnect.
    public func observingSince(for accountID: String) -> Date? {
        defaults.object(forKey: Self.sinceKey(for: accountID)) as? Date
    }

    /// Appends one sample per window in the snapshot. When a kind's used%
    /// fell (a reset), its prior samples are dropped first so the recorded
    /// series always lies within the current window.
    public func record(_ snapshot: UsageSnapshot, for accountID: String, at now: Date = Date()) {
        if defaults.object(forKey: Self.sinceKey(for: accountID)) == nil {
            defaults.set(now, forKey: Self.sinceKey(for: accountID))
        }
        var byKind = load(accountID)
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
        save(byKind, for: accountID)
    }

    public func clear(for accountID: String) {
        defaults.removeObject(forKey: Self.key(for: accountID))
        defaults.removeObject(forKey: Self.sinceKey(for: accountID))
    }

    // MARK: - Persistence

    private func load(_ accountID: String) -> [String: [UsageSample]] {
        guard let data = defaults.data(forKey: Self.key(for: accountID)) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: [UsageSample]].self, from: data)) ?? [:]
    }

    private func save(_ byKind: [String: [UsageSample]], for accountID: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(byKind) else { return }
        defaults.set(data, forKey: Self.key(for: accountID))
    }

    private static func key(for accountID: String) -> String {
        "usage.history.\(accountID)"
    }

    private static func sinceKey(for accountID: String) -> String {
        "usage.history.since.\(accountID)"
    }
}
