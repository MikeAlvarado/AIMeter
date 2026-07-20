import SwiftUI
import WidgetKit
import UsageKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let prefs: Preferences
}

/// Serves the last snapshot from the App Group. On iOS, when that snapshot
/// is older than the refresh cadence, the widget fetches fresh usage itself
/// (shared keychain credentials) so it keeps updating without the app;
/// on macOS the menu bar app feeds it. Timeline policy re-runs this at the
/// user-selected cadence, subject to WidgetKit's refresh budget.
struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .sample, prefs: Preferences())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(UsageEntry(date: .now, snapshot: .sample, prefs: Preferences()))
        } else {
            completion(entry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            var entry = entry()
            #if os(iOS)
            if let fresh = await WidgetRefresher.fetchIfStale(
                current: entry.snapshot,
                cadence: entry.prefs.refreshCadence.interval
            ) {
                entry = UsageEntry(date: .now, snapshot: fresh, prefs: entry.prefs)
            }
            #endif
            let next = Date(timeIntervalSinceNow: entry.prefs.refreshCadence.interval)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func entry() -> UsageEntry {
        UsageEntry(
            date: .now,
            snapshot: SnapshotStore(suiteName: AppConfig.appGroupID)?.snapshot(for: "claude"),
            prefs: Preferences.load()
        )
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConfig.widgetKind, provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude")
        .description("Session, weekly, and top-model usage windows.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

extension UsageSnapshot {
    static let sample = UsageSnapshot(
        providerID: "claude",
        planName: "pro",
        fetchedAt: .now,
        windows: [
            UsageWindow(kind: .session, usedPct: 42, resetsAt: .now.addingTimeInterval(3 * 3600)),
            UsageWindow(kind: .weekly, usedPct: 15, resetsAt: .now.addingTimeInterval(3 * 86400)),
            UsageWindow(kind: .modelSpecific("Fable"), usedPct: 9, resetsAt: .now.addingTimeInterval(3 * 86400)),
        ]
    )
}
