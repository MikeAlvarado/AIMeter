import SwiftUI
import WidgetKit
import UsageKit

struct SingleUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let accountID: String
    let kind: UsageWindow.Kind
    let accountName: String
    let prefs: Preferences

    var window: UsageWindow? {
        // Credits is synthesized from spend, never part of the real
        // windows array — same source WindowSlots uses for the dashboard.
        if kind == .credits { return snapshot?.creditsWindow }
        return snapshot?.windows.first { $0.kind == kind }
    }
}

/// Same App Group snapshot as `UsageTimelineProvider`, but renders only the
/// single window the user picked in Edit Widget. Falls back to Claude ·
/// session when unconfigured, so a freshly added widget still shows
/// something meaningful before the user edits it.
struct SingleUsageTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SingleUsageEntry {
        SingleUsageEntry(
            date: .now,
            snapshot: .sample,
            accountID: ClaudeKeychainCredentialSource.legacyAccountID,
            kind: .session,
            accountName: "Claude",
            prefs: Preferences()
        )
    }

    func snapshot(for configuration: SingleUsageConfigurationIntent, in context: Context) async -> SingleUsageEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        return entry(for: configuration)
    }

    func timeline(for configuration: SingleUsageConfigurationIntent, in context: Context) async -> Timeline<SingleUsageEntry> {
        var current = entry(for: configuration)
        // Floor the reload interval to stay within WidgetKit's refresh budget.
        let interval = max(current.prefs.refreshCadence.interval, AppConfig.widgetRefreshFloor)
        #if os(iOS)
        if let fresh = await WidgetRefresher.fetchIfStale(
            accountID: current.accountID,
            current: current.snapshot,
            cadence: interval
        ) {
            current = SingleUsageEntry(
                date: .now,
                snapshot: fresh,
                accountID: current.accountID,
                kind: current.kind,
                accountName: current.accountName,
                prefs: current.prefs
            )
        }
        #endif
        let next = Date(timeIntervalSinceNow: interval)
        var entries = [current]
        // Same trick as the main widget: an extra entry dated exactly at
        // the next peak transition lets WidgetKit flip the header's badge
        // on its own, with no extra refresh or network call.
        if let transition = PeakCalculator.nextTransition(after: current.date, schedule: ClaudePeakSchedule.current),
           transition < next {
            entries.append(SingleUsageEntry(
                date: transition,
                snapshot: current.snapshot,
                accountID: current.accountID,
                kind: current.kind,
                accountName: current.accountName,
                prefs: current.prefs
            ))
        }
        return Timeline(entries: entries, policy: .after(next))
    }

    private func entry(for configuration: SingleUsageConfigurationIntent) -> SingleUsageEntry {
        let selection = configuration.window
        // Same nil-configuration timing edge case as the 3-window widget:
        // fall back to the first real connected account instead of assuming
        // the legacy sentinel.
        let fallback = WidgetAccountFallback.resolve()
        let accountID = selection?.accountID ?? fallback.accountID
        let accountName = selection?.accountName ?? fallback.accountName
        return SingleUsageEntry(
            date: .now,
            snapshot: SnapshotStore(suiteName: AppConfig.appGroupID)?.snapshot(for: accountID),
            accountID: accountID,
            kind: selection?.kind ?? .session,
            accountName: accountName,
            prefs: Preferences.load()
        )
    }
}

struct SingleUsageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppConfig.singleWidgetKind,
            intent: SingleUsageConfigurationIntent.self,
            provider: SingleUsageTimelineProvider()
        ) { entry in
            SingleUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Single Limit")
        .description("Shows one usage window you choose — edit the widget to pick session, weekly, or a per-model limit.")
        .supportedFamilies([.systemSmall])
    }
}
