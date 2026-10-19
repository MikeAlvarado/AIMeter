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
    var layout: AllAccountsLayout = .standard

    /// The rows in the order the app shows accounts: the registry's, or
    /// by urgency with that switch on (`AccountOrder`), re-sorted after
    /// a self-fetch moved a figure.
    func ordered() -> AllAccountsEntry {
        guard prefs.ordersByUrgency else { return self }
        return AllAccountsEntry(date: date, rows: AccountOrder.byUrgency(rows) { $0.snapshot }, prefs: prefs, layout: layout)
    }
}

/// Large-only widget that always shows every connected account; unlike
/// `AIMeterUsage` there is no account to pick, and its one Edit Widget
/// choice is the layout (`AllAccountsConfigurationIntent`). Reads the
/// same App Group `AccountRegistryStore`/`SnapshotStore` every other
/// surface does; on iOS, self-refreshes whichever shown accounts are
/// stale, concurrently, the same way `UsageModel.refreshAll()` does in
/// the app.
struct AllAccountsTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AllAccountsEntry {
        AllAccountsEntry(
            date: .now, rows: [.init(account: ProviderCatalog.legacyAccount, snapshot: .sample)], prefs: Preferences()
        )
    }

    func snapshot(for configuration: AllAccountsConfigurationIntent, in context: Context) async -> AllAccountsEntry {
        if context.isPreview {
            var preview = placeholder(in: context)
            preview.layout = configuration.layout
            return preview
        }
        return currentEntry(layout: configuration.layout)
    }

    func timeline(for configuration: AllAccountsConfigurationIntent, in context: Context) async -> Timeline<AllAccountsEntry> {
        var current = currentEntry(layout: configuration.layout)
        // Same floor every other widget uses, so this stays within
        // WidgetKit's refresh budget regardless of display cadence.
        let interval = max(current.prefs.refreshCadence.interval, AppConfig.widgetRefreshFloor)
        #if os(iOS)
        current = await refreshingStaleRows(of: current, cadence: interval)
        #endif
        let next = WidgetSchedule.nextReload(
            after: current.date, interval: interval,
            resets: current.rows.flatMap { UsageTimelineProvider.resets(of: $0.snapshot) }
        )
        return Timeline(entries: [current], policy: .after(next))
    }

    private func currentEntry(layout: AllAccountsLayout) -> AllAccountsEntry {
        let registry = AccountRegistryStore(suiteName: AppConfig.appGroupID)
        let store = SnapshotStore(suiteName: AppConfig.appGroupID)
        let accounts = registry?.accounts() ?? []
        let rows = accounts.map { AllAccountsEntry.Row(account: $0, snapshot: store?.snapshot(for: $0.accountID)) }
        return AllAccountsEntry(date: .now, rows: rows, prefs: Preferences.load(), layout: layout).ordered()
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
        return AllAccountsEntry(date: entry.date, rows: rows, prefs: entry.prefs, layout: entry.layout).ordered()
    }
    #endif
}

struct AllAccountsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppConfig.allAccountsWidgetKind,
            intent: AllAccountsConfigurationIntent.self,
            provider: AllAccountsTimelineProvider()
        ) { entry in
            AllAccountsWidgetView(entry: entry)
        }
        .configurationDisplayName("All Accounts")
        .description("Every connected account's usage at a glance.")
        .supportedFamilies([.systemLarge])
    }
}
