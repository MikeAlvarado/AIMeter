import SwiftUI
import WidgetKit
import UsageKit

struct SingleUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let providerID: String
    let kind: UsageWindow.Kind
    let providerName: String
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
            providerID: "claude",
            kind: .session,
            providerName: "Claude",
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
            current: current.snapshot,
            cadence: interval
        ) {
            current = SingleUsageEntry(
                date: .now,
                snapshot: fresh,
                providerID: current.providerID,
                kind: current.kind,
                providerName: current.providerName,
                prefs: current.prefs
            )
        }
        #endif
        let next = Date(timeIntervalSinceNow: interval)
        return Timeline(entries: [current], policy: .after(next))
    }

    private func entry(for configuration: SingleUsageConfigurationIntent) -> SingleUsageEntry {
        let selection = configuration.window
        let providerID = selection?.providerID ?? "claude"
        return SingleUsageEntry(
            date: .now,
            snapshot: SnapshotStore(suiteName: AppConfig.appGroupID)?.snapshot(for: providerID),
            providerID: providerID,
            kind: selection?.kind ?? .session,
            providerName: selection?.providerName ?? "Claude",
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
