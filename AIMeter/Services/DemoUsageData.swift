import Foundation
import UsageKit

/// Fabricated snapshot for "View Demo" — lets someone explore every screen
/// (rate-limit rows, pace, peak hours, forecast, spend/extra usage cards)
/// without a real Claude account. Exists mainly so App Store reviewers can
/// evaluate the app without shared login credentials to a paid third-party
/// service, and doubles as a source of realistic-looking App Store
/// screenshots that doesn't expose anyone's real usage numbers.
enum DemoUsageData {
    static func snapshot(now: Date = Date()) -> UsageSnapshot {
        let weeklyReset = now.addingTimeInterval(3 * 86400 + 4 * 3600)
        return UsageSnapshot(
            providerID: ProviderCatalog.defaultProviderID,
            planName: "Demo",
            fetchedAt: now,
            windows: [
                UsageWindow(
                    kind: .session,
                    usedPct: 42,
                    resetsAt: now.addingTimeInterval(2 * 3600 + 59 * 60),
                    severity: .normal,
                    isActive: true
                ),
                UsageWindow(
                    kind: .weekly,
                    usedPct: 61,
                    resetsAt: weeklyReset,
                    severity: .normal,
                    isActive: true
                ),
                // Scoped weekly windows share the weekly window's exact
                // resetsAt (see UsageSnapshot data-shaping rules).
                // A neutral stand-in, not a real model name: demo mode is
                // what App Store screenshots are taken from, and screenshots
                // are store metadata — the app was rejected under 4.1(a) for
                // third-party names in metadata. Nothing in this fixture may
                // name a provider or one of its products.
                UsageWindow(
                    kind: .modelSpecific(String(localized: "Top model")),
                    usedPct: 18,
                    resetsAt: weeklyReset,
                    severity: .normal,
                    isActive: true
                )
            ],
            spend: SpendStatus(
                enabled: true,
                percent: 57,
                severity: .normal,
                usedAmount: 14.27,
                limitAmount: 25.00,
                currency: "USD"
            ),
            extraUsage: ExtraUsageStatus(
                enabled: true,
                usedCredits: 3.5,
                monthlyLimit: 20,
                utilization: 17.5,
                currency: "USD"
            )
        )
    }

    /// The demo's second account — "Work", a busier week on a plan with no
    /// per-model window, so the third row shows the credits fallback and
    /// the dashboard reads as two genuinely different accounts. Carries a
    /// symbol icon (`briefcase.fill`) so screenshots show the per-account
    /// icon without a brand mark.
    static func secondSnapshot(now: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            providerID: ProviderCatalog.defaultProviderID,
            planName: "Demo",
            fetchedAt: now.addingTimeInterval(-4 * 60),
            windows: [
                UsageWindow(
                    kind: .session,
                    usedPct: 73,
                    resetsAt: now.addingTimeInterval(1 * 3600 + 12 * 60),
                    severity: .normal,
                    isActive: true
                ),
                UsageWindow(
                    kind: .weekly,
                    usedPct: 28,
                    resetsAt: now.addingTimeInterval(5 * 86400 + 9 * 3600),
                    severity: .normal,
                    isActive: true
                ),
            ],
            spend: SpendStatus(
                enabled: true,
                percent: 31,
                severity: .normal,
                usedAmount: 7.75,
                limitAmount: 25.00,
                currency: "USD"
            )
        )
    }

    /// The accounts demo mode shows, each with the snapshot it reports:
    /// "Personal" on the default mark and "Work" on a symbol. Neutral
    /// nicknames on purpose — the demo is the source of App Store
    /// screenshots, and a provider's name in a screenshot is a third-party
    /// name in store metadata (4.1(a)).
    static func accounts(now: Date = Date()) -> [(account: ConnectedAccount, snapshot: UsageSnapshot)] {
        [
            (ConnectedAccount(
                accountID: "demo", providerID: ProviderCatalog.defaultProviderID,
                displayName: "Personal", credentialStrategy: .managed
            ), snapshot(now: now)),
            (ConnectedAccount(
                accountID: "demo-2", providerID: ProviderCatalog.defaultProviderID,
                displayName: "Work", credentialStrategy: .managed, icon: .symbol("briefcase.fill")
            ), secondSnapshot(now: now)),
        ]
    }

    /// Thirty days of fabricated samples per window, ending exactly on the
    /// figures `snapshot` reports now (the first demo account's by
    /// default), so the History card and the dashboard sparklines have
    /// something to draw in demo mode (and in screenshots). Sessions are a
    /// 5-hour sawtooth with a different height each cycle; the weekly
    /// windows reset once, where the snapshot's own reset date says the
    /// current week began, and once a week before that at varying heights.
    static func timeline(now: Date = Date(), for snapshot: UsageSnapshot? = nil) -> [String: [TimelineSample]] {
        let snapshot = snapshot ?? self.snapshot(now: now)
        let step: TimeInterval = 30 * 60
        let span: TimeInterval = 30 * 86400
        let sessionLength: TimeInterval = 5 * 3600
        let sessionPct = snapshot.sessionWindow?.usedPct ?? 42
        let weeklyPct = snapshot.weeklyWindow?.usedPct ?? 61
        let modelWindow = snapshot.modelWindows.first
        let modelPct = modelWindow?.usedPct ?? 18
        // The current session started 5 hours before its reset date.
        let sessionStart = (snapshot.sessionWindow?.resetsAt ?? now.addingTimeInterval(2 * 3600 + 59 * 60))
            .addingTimeInterval(-sessionLength)
        // The live figure isn't a straight line from 0; scale the live
        // cycle so its last sample lands on it.
        let positionNow = now.timeIntervalSince(sessionStart) / sessionLength
        let liveHeight = sessionPct / positionNow
        let weekStart = (snapshot.weeklyWindow?.resetsAt ?? now.addingTimeInterval(3 * 86400 + 4 * 3600))
            .addingTimeInterval(-7 * 86400)

        var session: [TimelineSample] = []
        var weekly: [TimelineSample] = []
        var model: [TimelineSample] = []
        var t = now.addingTimeInterval(-span)
        while t <= now {
            let elapsed = t.timeIntervalSince(sessionStart)
            let cycle = floor(elapsed / sessionLength)
            let position = (elapsed - cycle * sessionLength) / sessionLength
            // Cycle 0 is the live one, which must end on the live figure;
            // earlier cycles vary in height so the chart isn't a flat sawtooth.
            let height = cycle == 0 ? liveHeight : 55 + 40 * abs(sin(cycle * 1.7))
            let resetsAt = sessionStart.addingTimeInterval((cycle + 1) * sessionLength)
            // Nights are idle — no session, 0 %, no reset date — so a week
            // reads as days of work, not one unbroken comb. The last
            // sample is always the live figure, whatever the hour.
            let hour = Calendar.current.component(.hour, from: t)
            let idle = (hour < 8 || hour >= 22) && t < now
            session.append(idle
                ? TimelineSample(timestamp: t, usedPct: 0, resetsAt: nil)
                : TimelineSample(timestamp: t, usedPct: (position * height).rounded(), resetsAt: resetsAt))

            // Week 0 is the live one (ending exactly on the live figures);
            // earlier weeks (-1, -2, …) each top out at a different height.
            let weekIndex = floor(t.timeIntervalSince(weekStart) / (7 * 86400))
            let weekAnchor = weekStart.addingTimeInterval(weekIndex * 7 * 86400)
            let weekPosition = t.timeIntervalSince(weekAnchor) / (7 * 86400)
            let livePosition = now.timeIntervalSince(weekStart) / (7 * 86400)
            let weeklyTarget = weekIndex == 0 ? weeklyPct / livePosition : 62 + 30 * abs(sin(weekIndex * 1.3))
            let modelTarget = weekIndex == 0 ? modelPct / livePosition : 18 + 16 * abs(sin(weekIndex * 0.9))
            let weekReset = weekAnchor.addingTimeInterval(7 * 86400)
            weekly.append(TimelineSample(timestamp: t, usedPct: (min(99, weekPosition * weeklyTarget) * 10).rounded() / 10, resetsAt: weekReset))
            model.append(TimelineSample(timestamp: t, usedPct: (min(99, weekPosition * modelTarget) * 10).rounded() / 10, resetsAt: weekReset))
            t = t.addingTimeInterval(step)
        }
        var series = [
            UsageWindow.Kind.session.storageKey: session,
            UsageWindow.Kind.weekly.storageKey: weekly,
        ]
        if let modelWindow {
            series[modelWindow.kind.storageKey] = model
        }
        return series
    }

    /// Fabricated "coding sessions on this Mac" figures for the macOS
    /// demo (the Claude Code section), one aggregate per bucket, nesting
    /// the way rolling windows do. Model names are neutral stand-ins for
    /// the same reason the account is "Personal": screenshots are store
    /// metadata.
    static func codingSessions(_ bucket: String) -> ClaudeCodeUsageAggregate {
        func model(_ name: String, _ total: Int, _ cost: Double, _ messages: Int) -> ClaudeCodeUsageAggregate.ModelUsage {
            let tokens = ClaudeCodeTokenCounts(
                input: total / 20, output: total / 40, thinking: total / 200,
                cacheWrite5m: total / 10, cacheWrite1h: total / 50, cacheRead: total - total / 20 - total / 40 - total / 10 - total / 50,
                webSearches: messages / 12
            )
            return .init(model: name, tokens: tokens, cost: cost, messages: messages)
        }
        let rows: [ClaudeCodeUsageAggregate.ModelUsage]
        let sessions: Int
        switch bucket {
        case "today":
            rows = [model(String(localized: "Top model"), 9_400_000, 7.10, 118), model(String(localized: "Everyday model"), 2_600_000, 1.45, 61), model(String(localized: "Fast model"), 410_000, 0.12, 24)]
            sessions = 3
        case "week":
            rows = [model(String(localized: "Top model"), 61_200_000, 44.80, 702), model(String(localized: "Everyday model"), 19_700_000, 10.95, 388), model(String(localized: "Fast model"), 3_600_000, 1.05, 190)]
            sessions = 17
        case "month":
            rows = [model(String(localized: "Top model"), 226_000_000, 163.20, 2_610), model(String(localized: "Everyday model"), 71_300_000, 39.60, 1_422), model(String(localized: "Fast model"), 12_900_000, 3.70, 690)]
            sessions = 64
        default:
            rows = [model(String(localized: "Top model"), 812_000_000, 585.00, 9_380), model(String(localized: "Everyday model"), 254_000_000, 141.20, 5_061), model(String(localized: "Fast model"), 47_500_000, 13.60, 2_480)]
            sessions = 231
        }
        return ClaudeCodeUsageAggregate(
            tokens: rows.reduce(ClaudeCodeTokenCounts()) { $0 + $1.tokens },
            cost: rows.compactMap(\.cost).reduce(0, +),
            messages: rows.reduce(0) { $0 + $1.messages },
            sessions: sessions,
            byModel: rows
        )
    }
}
