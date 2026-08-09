import SwiftUI
import WidgetKit
import UsageKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let accountID: String
    let accountName: String
    let prefs: Preferences
}

/// Serves the last snapshot from the App Group, for whichever account the
/// user picked in Edit Widget (`UsageAccountConfigurationIntent`) — every
/// placed instance, Home Screen or Lock Screen, has its own independent
/// account selection. On iOS, when that snapshot is older than the refresh
/// cadence, the widget fetches fresh usage itself (shared keychain
/// credentials) so it keeps updating without the app; on macOS the menu bar
/// app feeds it. Timeline policy re-runs this at the user-selected cadence,
/// subject to WidgetKit's refresh budget.
struct UsageTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .sample, accountID: ClaudeKeychainCredentialSource.legacyAccountID, accountName: "Claude", prefs: Preferences())
    }

    func snapshot(for configuration: UsageAccountConfigurationIntent, in context: Context) async -> UsageEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        return entry(for: configuration)
    }

    func timeline(for configuration: UsageAccountConfigurationIntent, in context: Context) async -> Timeline<UsageEntry> {
        var current = entry(for: configuration)
        // Floor the widget's own reload interval so it stays within
        // WidgetKit's refresh budget regardless of the display cadence.
        let interval = max(current.prefs.refreshCadence.interval, AppConfig.widgetRefreshFloor)
        #if os(iOS)
        if let fresh = await WidgetRefresher.fetchIfStale(
            accountID: current.accountID,
            current: current.snapshot,
            cadence: interval
        ) {
            current = UsageEntry(date: .now, snapshot: fresh, accountID: current.accountID, accountName: current.accountName, prefs: current.prefs)
        }
        #endif
        let next = Date(timeIntervalSinceNow: interval)
        return Timeline(entries: [current] + peakTransitionEntry(after: current, before: next), policy: .after(next))
    }

    /// If Claude's peak-hours schedule flips before the next scheduled
    /// reload, an extra entry dated exactly at that transition makes
    /// WidgetKit switch the header's peak badge on its own at the right
    /// wall-clock moment — no extra refresh or network call, since peak
    /// state is a pure function of the entry's own `date`.
    private func peakTransitionEntry(after entry: UsageEntry, before next: Date) -> [UsageEntry] {
        guard let transition = PeakCalculator.nextTransition(after: entry.date, schedule: ClaudePeakSchedule.current),
              transition < next else { return [] }
        return [UsageEntry(date: transition, snapshot: entry.snapshot, accountID: entry.accountID, accountName: entry.accountName, prefs: entry.prefs)]
    }

    private func entry(for configuration: UsageAccountConfigurationIntent) -> UsageEntry {
        // configuration.account is nil right after a widget is first placed,
        // before WidgetKit has applied the intent's own default selection —
        // fall back to the first real connected account (matching
        // `UsageAccountOptionQuery.defaultResult()`) rather than assuming
        // the legacy sentinel, which a fresh multi-account install never uses.
        let fallback = WidgetAccountFallback.resolve()
        let accountID = configuration.account?.accountID ?? fallback.accountID
        let accountName = configuration.account?.accountName ?? fallback.accountName
        return UsageEntry(
            date: .now,
            snapshot: SnapshotStore(suiteName: AppConfig.appGroupID)?.snapshot(for: accountID),
            accountID: accountID,
            accountName: accountName,
            prefs: Preferences.load()
        )
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppConfig.widgetKind,
            intent: UsageAccountConfigurationIntent.self,
            provider: UsageTimelineProvider()
        ) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude")
        .description("Session, weekly, and top-model usage windows — edit the widget to pick which account.")
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
