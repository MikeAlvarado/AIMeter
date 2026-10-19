import Foundation
import UsageKit

/// What a widget's placeholder and the gallery preview draw: plausible
/// figures, no account, no provider name beyond the default's.
extension UsageSnapshot {
    static let sample = UsageSnapshot(
        providerID: ProviderCatalog.defaultProviderID,
        planName: "pro",
        fetchedAt: .now,
        windows: [
            UsageWindow(kind: .session, usedPct: 42, resetsAt: .now.addingTimeInterval(3 * 3600)),
            UsageWindow(kind: .weekly, usedPct: 15, resetsAt: .now.addingTimeInterval(3 * 86400)),
            UsageWindow(kind: .modelSpecific("Fable"), usedPct: 9, resetsAt: .now.addingTimeInterval(3 * 86400)),
        ]
    )
}
