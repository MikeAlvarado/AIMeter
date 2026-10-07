import Foundation
import UsageKit

/// The chart's data, read from `UsageTimelineStore` once per account and
/// kept in memory (`timelines`) so the Dashboard's sparklines don't
/// re-read a file on every body evaluation — a drag-reorder evaluates
/// bodies per frame. Reloaded after each successful fetch (the one time
/// the file changes from this process) and on each foreground sweep (the
/// iOS widget may have appended in between).
extension UsageModel {
    func timeline(for accountID: String, kind: UsageWindow.Kind) -> [TimelineSample] {
        if isDemoMode {
            // Each demo account's series ends on its own snapshot's figures.
            let snapshot = accounts.first { $0.account.accountID == accountID }?.snapshot
            return DemoUsageData.timeline(for: snapshot)[kind.storageKey] ?? []
        }
        return timelines[accountID]?[kind.storageKey] ?? []
    }

    func reloadTimeline(for accountID: String) {
        guard let timelineStore else { return }
        timelines[accountID] = timelineStore.allSamples(for: accountID)
    }

    func reloadTimelines() {
        guard timelineStore != nil else { return }
        var loaded: [String: [String: [TimelineSample]]] = [:]
        for usage in accounts {
            loaded[usage.account.accountID] = timelineStore?.allSamples(for: usage.account.accountID)
        }
        timelines = loaded
    }
}
