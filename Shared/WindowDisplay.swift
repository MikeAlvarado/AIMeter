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

/// How close a window is to its limit — the one decision behind every
/// bar and percentage color. Terracotta up to 70 % used, yellow from 71 % (or
/// when the provider flags a warning), red from 86 % (or when the
/// provider flags trouble). Three colors, nothing else — and only while
/// the user keeps usage colors on (`Preferences.usageColors`); off, every
/// bar draws at `.normal`.
enum UsageLevel: Int, Comparable {
    case normal, warning, danger

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Usage *above* these turns the level: 70 % is still terracotta, 85 % still
    /// yellow.
    static let warningAbove: Double = 70
    static let dangerAbove: Double = 85

    init(usedPct: Double, severity: UsageWindow.Severity?) {
        // Compared on the whole percent every surface prints (they all
        // truncate), so a bar that reads "70%" is never yellow and one that
        // reads "85%" is never red; the endpoint does report fractions.
        let shown = usedPct.rounded(.down)
        if severity == .critical || severity == .exceeded || shown > Self.dangerAbove {
            self = .danger
        } else if severity == .warning || shown > Self.warningAbove {
            self = .warning
        } else {
            self = .normal
        }
    }

    var color: Color {
        switch self {
        case .normal: Theme.accent
        case .warning: Theme.warning
        case .danger: Theme.danger
        }
    }
}

extension UsageWindow {
    var level: UsageLevel { UsageLevel(usedPct: usedPct, severity: severity) }

    /// The level the bar is drawn at: `level`, or `.normal` at every figure
    /// while usage colors are off (`Preferences.usageColors`).
    func level(usageColors: Bool) -> UsageLevel { usageColors ? level : .normal }

    /// The bar's color — `level(usageColors:)`'s.
    func tint(usageColors: Bool) -> Color { level(usageColors: usageColors).color }

    /// Same decision as `tint(usageColors:)`, callable without a full
    /// `UsageWindow` — the Live Activity only carries `usedPct`/`severity`
    /// in its `ContentState` (not a whole window), so it needs this
    /// reusable instead of duplicating the thresholds.
    static func tint(usedPct: Double, severity: Severity?, usageColors: Bool) -> Color {
        (usageColors ? UsageLevel(usedPct: usedPct, severity: severity) : .normal).color
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
