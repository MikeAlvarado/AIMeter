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
            // Floor the widget's own reload interval so it stays within
            // WidgetKit's refresh budget regardless of the display cadence.
            let interval = max(entry.prefs.refreshCadence.interval, AppConfig.widgetRefreshFloor)
            #if os(iOS)
            if let fresh = await WidgetRefresher.fetchIfStale(
                current: entry.snapshot,
                cadence: interval
            ) {
                entry = UsageEntry(date: .now, snapshot: fresh, prefs: entry.prefs)
            }
            #endif
            let next = Date(timeIntervalSinceNow: interval)
            completion(Timeline(entries: [entry] + peakTransitionEntry(after: entry, before: next), policy: .after(next)))
        }
    }

    /// If Claude's peak-hours schedule flips before the next scheduled
    /// reload, an extra entry dated exactly at that transition makes
    /// WidgetKit switch the header's peak badge on its own at the right
    /// wall-clock moment — no extra refresh or network call, since peak
    /// state is a pure function of the entry's own `date`.
    private func peakTransitionEntry(after entry: UsageEntry, before next: Date) -> [UsageEntry] {
        guard let transition = PeakCalculator.nextTransition(after: entry.date, schedule: ClaudePeakSchedule.current),
              transition < next else { return [] }
        return [UsageEntry(date: transition, snapshot: entry.snapshot, prefs: entry.prefs)]
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
