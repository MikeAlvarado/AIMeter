import SwiftUI
import WidgetKit
import UsageKit

struct AllAccountsEntry: TimelineEntry {
    struct Row: Identifiable {
        let account: ConnectedAccount
        let snapshot: UsageSnapshot?
        var id: String { account.accountID }
    }
    let date: Date
    let rows: [Row]
    let prefs: Preferences
}

/// Large-only widget with no per-instance configuration — unlike
/// `AIMeterUsage`, there's nothing to pick, it always shows every connected
/// account. Reads the same App Group `AccountRegistryStore`/`SnapshotStore`
/// every other surface does; on iOS, self-refreshes whichever shown
/// accounts are stale, concurrently, the same way `UsageModel.refreshAll()`
/// does in the app.
struct AllAccountsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> AllAccountsEntry {
        let sample = ConnectedAccount(
            accountID: ClaudeKeychainCredentialSource.legacyAccountID, providerID: "claude",
            displayName: "Claude", credentialStrategy: .managed
        )
        return AllAccountsEntry(date: .now, rows: [.init(account: sample, snapshot: .sample)], prefs: Preferences())
    }

    func getSnapshot(in context: Context, completion: @escaping (AllAccountsEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await currentEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AllAccountsEntry>) -> Void) {
        Task {
            var current = await currentEntry()
            // Same floor every other widget uses, so this stays within
            // WidgetKit's refresh budget regardless of display cadence.
            let interval = max(current.prefs.refreshCadence.interval, AppConfig.widgetRefreshFloor)
            #if os(iOS)
            current = await refreshingStaleRows(of: current, cadence: interval)
            #endif
            let next = Date(timeIntervalSinceNow: interval)
            completion(Timeline(entries: [current], policy: .after(next)))
        }
    }

    private func currentEntry() async -> AllAccountsEntry {
        let registry = AccountRegistryStore(suiteName: AppConfig.appGroupID)
        let store = SnapshotStore(suiteName: AppConfig.appGroupID)
        let accounts = registry?.accounts() ?? []
        let rows = accounts.map { AllAccountsEntry.Row(account: $0, snapshot: store?.snapshot(for: $0.accountID)) }
        return AllAccountsEntry(date: .now, rows: rows, prefs: Preferences.load())
    }

    #if os(iOS)
    private func refreshingStaleRows(of entry: AllAccountsEntry, cadence: TimeInterval) async -> AllAccountsEntry {
        let fetched = await withTaskGroup(of: (String, UsageSnapshot?).self) { group in
            for row in entry.rows {
                group.addTask {
                    let fresh = await WidgetRefresher.fetchIfStale(
                        accountID: row.account.accountID, current: row.snapshot, cadence: cadence
                    )
                    return (row.account.accountID, fresh)
                }
            }
            var results: [String: UsageSnapshot] = [:]
            for await (accountID, snapshot) in group {
                if let snapshot { results[accountID] = snapshot }
            }
            return results
        }
        let rows = entry.rows.map { row in
            AllAccountsEntry.Row(account: row.account, snapshot: fetched[row.account.accountID] ?? row.snapshot)
        }
        return AllAccountsEntry(date: entry.date, rows: rows, prefs: entry.prefs)
    }
    #endif
}

struct AllAccountsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConfig.allAccountsWidgetKind, provider: AllAccountsTimelineProvider()) { entry in
            AllAccountsWidgetView(entry: entry)
        }
        .configurationDisplayName("All Accounts")
        .description("Every connected account's usage at a glance.")
        .supportedFamilies([.systemLarge])
    }
}
