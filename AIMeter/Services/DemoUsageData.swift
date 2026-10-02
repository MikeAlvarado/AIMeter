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

    /// Seven days of fabricated samples per window, ending exactly on the
    /// figures `snapshot()` reports now, so the History card and the
    /// dashboard sparklines have something to draw in demo mode (and in
    /// screenshots). Sessions are a 5-hour sawtooth with a different
    /// height each cycle; the weekly windows reset once, where the
    /// snapshot's own reset date says the current week began.
    static func timeline(now: Date = Date()) -> [String: [TimelineSample]] {
        let step: TimeInterval = 30 * 60
        let span: TimeInterval = 7 * 86400
        let sessionLength: TimeInterval = 5 * 3600
        // The current session is 42% through its 5 hours (2h59m to go).
        let sessionStart = now.addingTimeInterval(-(sessionLength - (2 * 3600 + 59 * 60)))
        // The snapshot's 42 % with 2h59m left isn't a straight line from 0;
        // scale the live cycle so its last sample lands on the figure.
        let positionNow = now.timeIntervalSince(sessionStart) / sessionLength
        let liveHeight = 42 / positionNow
        let weekStart = now.addingTimeInterval(3 * 86400 + 4 * 3600 - 7 * 86400)

        var session: [TimelineSample] = []
        var weekly: [TimelineSample] = []
        var model: [TimelineSample] = []
        var t = now.addingTimeInterval(-span)
        while t <= now {
            let elapsed = t.timeIntervalSince(sessionStart)
            let cycle = floor(elapsed / sessionLength)
            let position = (elapsed - cycle * sessionLength) / sessionLength
            // Cycle 0 is the live one, which must end at 42%; earlier
            // cycles vary in height so the chart isn't a flat sawtooth.
            let height = cycle == 0 ? liveHeight : 55 + 40 * abs(sin(cycle * 1.7))
            let resetsAt = sessionStart.addingTimeInterval((cycle + 1) * sessionLength)
            session.append(TimelineSample(timestamp: t, usedPct: (position * height).rounded(), resetsAt: resetsAt))

            let inCurrentWeek = t >= weekStart
            let weekAnchor = inCurrentWeek ? weekStart : weekStart.addingTimeInterval(-7 * 86400)
            let weekPosition = t.timeIntervalSince(weekAnchor) / (7 * 86400)
            let weeklyTarget = inCurrentWeek ? 61.0 / (now.timeIntervalSince(weekStart) / (7 * 86400)) : 78
            let modelTarget = inCurrentWeek ? 18.0 / (now.timeIntervalSince(weekStart) / (7 * 86400)) : 31
            let weekReset = weekAnchor.addingTimeInterval(7 * 86400)
            weekly.append(TimelineSample(timestamp: t, usedPct: min(99, weekPosition * weeklyTarget).rounded(), resetsAt: weekReset))
            model.append(TimelineSample(timestamp: t, usedPct: min(99, weekPosition * modelTarget).rounded(), resetsAt: weekReset))
            t = t.addingTimeInterval(step)
        }
        return [
            UsageWindow.Kind.session.storageKey: session,
            UsageWindow.Kind.weekly.storageKey: weekly,
            UsageWindow.Kind.modelSpecific(String(localized: "Top model")).storageKey: model,
        ]
    }
}
