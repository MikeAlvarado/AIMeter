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
            providerID: "claude",
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
                UsageWindow(
                    kind: .modelSpecific("Fable 5"),
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
}
