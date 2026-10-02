import Foundation
import UsageKit

/// The one place a persisted snapshot is also written into the two
/// history stores — `UsageHistoryStore` (the run-out predictor's short,
/// reset-aware series) and `UsageTimelineStore` (the chart's long,
/// reset-preserving one). Called by `RefreshService` and the iOS widget's
/// self-fetch, so neither can forget the other store.
nonisolated enum UsageRecorder {
    static func record(_ snapshot: UsageSnapshot, for accountID: String) {
        UsageHistoryStore(suiteName: AppConfig.appGroupID)?.record(snapshot, for: accountID)
        UsageTimelineStore(appGroupID: AppConfig.appGroupID)?.record(snapshot, for: accountID)
    }

    /// Part of the disconnect cascade.
    static func clear(accountID: String) {
        UsageHistoryStore(suiteName: AppConfig.appGroupID)?.clear(for: accountID)
        UsageTimelineStore(appGroupID: AppConfig.appGroupID)?.clear(for: accountID)
    }
}
