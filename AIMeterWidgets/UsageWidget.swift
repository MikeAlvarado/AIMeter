import SwiftUI
import WidgetKit
import UsageKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let prefs: Preferences
}

/// Reads the last snapshot and display preferences from the App Group;
/// never fetches. The app (or its background task) refreshes data and
/// reloads timelines. Entries only re-render so staleness stays current.
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
        let entry = entry()
        let next = Date(timeIntervalSinceNow: entry.prefs.refreshCadence.interval)
        completion(Timeline(entries: [entry], policy: .after(next)))
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
        .configurationDisplayName("Claude Usage")
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
