import Foundation
import UsageKit

/// How the macOS status item draws the primary account's usage. Stored as
/// `Preferences.menuBarStyle`; an install from before styles existed is
/// migrated from the old "Show percentage" bool (`migrated(showsPercentage:)`)
/// so an upgrade never changes what's in the menu bar.
enum MenuBarStyle: String, CaseIterable, Sendable {
    /// The gauge with the number beside it — what shipped first.
    case gaugeWithPercent
    /// The gauge alone; the number stays in the tooltip.
    case gaugeOnly
    case percentOnly
    /// A small horizontal bar that fills with the displayed figure.
    case bar
    /// A battery outline that fills with the displayed figure — reads
    /// best with "Remaining", where it drains as you use.
    case battery
    /// Two or three windows as compact text ("S 42% · W 18%").
    case multi

    var label: String {
        switch self {
        case .gaugeWithPercent: String(localized: "Gauge and percentage")
        case .gaugeOnly: String(localized: "Gauge only")
        case .percentOnly: String(localized: "Percentage only")
        case .bar: String(localized: "Bar")
        case .battery: String(localized: "Battery")
        case .multi: String(localized: "Several windows")
        }
    }

    static func migrated(showsPercentage: Bool) -> MenuBarStyle {
        showsPercentage ? .gaugeWithPercent : .gaugeOnly
    }
}

/// Everything the status item label shows, computed once from the
/// snapshot and the preferences and handed to the view, which only draws
/// it. Pure so the text, fraction and tint rules are unit-tested rather
/// than eyeballed in a menu bar.
struct MenuBarLabelModel: Equatable {
    enum Tint: Equatable { case normal, danger }

    static let maxMetrics = 3
    /// A nickname longer than this is cut: the status item has no room
    /// to spare and the full name stays in the accessibility label.
    static let accountNameLimit = 8

    let style: MenuBarStyle
    /// Spelled-out part beside (or instead of) the glyph; nil for a
    /// glyph-only label.
    let text: String?
    /// 0–1 for the gauge, bar and battery, following the *displayed*
    /// figure so a "Remaining" reading never contradicts its own glyph.
    let fraction: Double
    let tint: Tint
    /// Always carries the full value(s), regardless of style — icon-only
    /// mode must never be the only place the number lived.
    let accessibilityLabel: String

    init(
        snapshot: UsageSnapshot?,
        displayMode: DisplayMode,
        style: MenuBarStyle,
        metric: UsageWindow.Kind,
        metrics: [UsageWindow.Kind],
        modelSlotFallback: ModelSlotFallback,
        tintsAtDanger: Bool,
        showsCountdown: Bool,
        accountName: String?,
        now: Date = Date()
    ) {
        self.style = style
        let available = UsageSnapshot.glanceOptions(for: snapshot, modelSlotFallback: modelSlotFallback)
        let kinds: [UsageWindow.Kind]
        if style == .multi {
            let chosen = Array(metrics.filter(available.contains).prefix(Self.maxMetrics))
            kinds = chosen.isEmpty ? [metric] : chosen
        } else {
            kinds = [metric]
        }
        let windows = kinds.compactMap { kind in snapshot?.window(for: kind).map { (kind, $0) } }
        let primary = windows.first?.1

        fraction = primary.map { min(max($0.displayedPct(displayMode) / 100, 0), 1) } ?? 0
        let isDanger: (UsageWindow) -> Bool = { window in
            tintsAtDanger && (window.severity == .critical || window.severity == .exceeded || window.usedPct >= 80)
        }
        tint = windows.contains { isDanger($0.1) } ? .danger : .normal

        let shortName = accountName.map { String($0.prefix(Self.accountNameLimit)) }
        let countdown: String? = {
            guard showsCountdown, style != .multi, let resetsAt = primary?.resetsAt, resetsAt > now else { return nil }
            return UsageFormatting.relativeString(from: now, to: resetsAt)
        }()

        var parts: [String] = []
        if style == .multi {
            parts = windows.map { "\(Self.abbreviation($0.0)) \(Int($0.1.displayedPct(displayMode)))%" }
        } else if style != .gaugeOnly, let primary {
            parts = ["\(Int(primary.displayedPct(displayMode)))%"]
        }
        if let countdown { parts.append(countdown) }
        var joined = parts.joined(separator: " · ")
        if let shortName {
            joined = joined.isEmpty ? shortName : "\(shortName) \(joined)"
        }
        text = joined.isEmpty ? nil : joined

        guard !windows.isEmpty else {
            accessibilityLabel = String(localized: "AIMeter — no usage data yet")
            return
        }
        var spoken = windows.map { kind, window in
            String(localized: "\(kind.shortName): \(Int(window.displayedPct(displayMode)))% \(displayMode.label)")
        }.joined(separator: ", ")
        if let countdown {
            spoken += ", " + String(localized: "resets in \(countdown)")
        }
        if let accountName {
            spoken = "\(accountName) — \(spoken)"
        }
        accessibilityLabel = spoken
    }

    /// One or two letters per window for the multi style. Localized, since
    /// "Session" and "Semana" would otherwise collide on "S".
    static func abbreviation(_ kind: UsageWindow.Kind) -> String {
        switch kind {
        case .session: String(localized: "S")
        case .weekly: String(localized: "W")
        case .modelSpecific(let model): String(model.prefix(1)).uppercased()
        case .credits: String(localized: "C")
        }
    }
}
