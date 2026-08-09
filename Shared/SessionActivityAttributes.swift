#if os(iOS)
import ActivityKit
import Foundation
import UsageKit

/// Data behind the Session-window Live Activity — lives in `Shared/` since
/// both the app (starts/updates/ends it) and the widget extension (renders
/// it) need the type. iOS only: ActivityKit doesn't exist on macOS.
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var usedPct: Double
        var resetsAt: Date
        var isPeak: Bool
        /// Carried alongside `usedPct` so `UsageWindow.tint(usedPct:severity:)`
        /// can make the same red/terracotta call every other surface makes —
        /// a provider-flagged "critical"/"exceeded" window should turn red
        /// here too, not just past the raw percentage threshold.
        var severity: UsageWindow.Severity?
    }

    let accountID: String
    let accountName: String
}
#endif
