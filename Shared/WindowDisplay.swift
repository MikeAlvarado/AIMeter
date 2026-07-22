import SwiftUI
import UsageKit

/// Presentation helpers shared by app and widgets. Rendering is driven by
/// whatever windows the snapshot contains — no provider names hardcoded.
extension UsageWindow.Kind {
    /// Row title on dashboard/detail: "5-hour session", "Weekly",
    /// "Weekly · Fable".
    var displayName: String {
        switch self {
        case .session: return String(localized: "5-hour session")
        case .weekly: return String(localized: "Weekly")
        case .modelSpecific(let model): return String(localized: "Weekly · \(model)")
        case .credits: return String(localized: "Credits")
        }
    }

    /// Compact label for widgets and the menu bar.
    var shortName: String {
        switch self {
        case .session: return String(localized: "Session")
        case .weekly: return String(localized: "Week")
        case .modelSpecific(let model): return model
        case .credits: return String(localized: "Credits")
        }
    }

    var symbolName: String {
        switch self {
        case .session: return "clock"
        case .weekly: return "calendar"
        case .modelSpecific: return "sparkles"
        case .credits: return "creditcard"
        }
    }
}

extension UsageWindow {
    /// Terracotta throughout; red only when the provider flags trouble or
    /// the window is nearly exhausted. Two colors, nothing else.
    var tint: Color {
        if severity == .critical || severity == .exceeded || usedPct >= 90 {
            return Theme.danger
        }
        return Theme.accent
    }
}

extension UsageSnapshot {
    var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > AppConfig.staleAfter
    }
}

extension UsagePace.Status {
    /// Short caption shown next to the reset line. Localized in the app's
    /// catalog (UsageKit core carries no UI strings beyond errors).
    var label: String {
        switch self {
        case .onPace: return String(localized: "On pace")
        case .ahead: return String(localized: "Ahead of pace")
        case .behind: return String(localized: "Behind pace")
        }
    }
}
