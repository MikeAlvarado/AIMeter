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
        }
    }

    /// Compact label for widgets and the menu bar.
    var shortName: String {
        switch self {
        case .session: return String(localized: "5h")
        case .weekly: return String(localized: "Week")
        case .modelSpecific(let model): return model
        }
    }

    var symbolName: String {
        switch self {
        case .session: return "clock"
        case .weekly: return "calendar"
        case .modelSpecific: return "sparkles"
        }
    }

    /// Stable key for per-window settings (e.g. notification toggles).
    var storageKey: String {
        switch self {
        case .session: return "session"
        case .weekly: return "weekly"
        case .modelSpecific(let model): return "model.\(model)"
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
