import Foundation
import UsageKit

/// Which side(s) of the physical notch the wings open on when the cursor
/// rests on the island (the peek), and which the expanded island's header
/// uses. Stored as `Preferences.notchIslandLayout`; the floating pill a
/// Mac without a notch gets has no sides, so it shows its one row always.
enum NotchIslandLayout: String, CaseIterable, Sendable {
    /// First metric left of the notch, the rest to its right.
    case bothSides
    case leftOnly
    case rightOnly

    var label: String {
        switch self {
        case .bothSides: String(localized: "Both sides")
        case .leftOnly: String(localized: "Left")
        case .rightOnly: String(localized: "Right")
        }
    }
}

/// Everything the macOS notch island shows, computed once from the
/// connected accounts' snapshots and the preferences and handed to the
/// views, which only draw it. Sibling of `MenuBarLabelModel`: pure, no
/// AppKit, so the label, percentage, tint, status and collapsed-layout
/// rules are unit-tested instead of eyeballed under a notch. Nothing
/// here is the only place a figure lives — the popover, the Dashboard
/// and the tooltip carry the same data.
struct NotchIslandModel: Equatable {
    enum Tint: Equatable { case normal, danger }

    /// One account's footer line, in priority order: a dead login beats
    /// a network error beats a provider error beats age.
    enum Status: Equatable {
        case fresh
        /// The snapshot is older than `AppConfig.staleAfter`; carries the
        /// "Updated 31 min ago" caption.
        case stale(String)
        case offline
        case reauth
        /// The raw endpoint body, per the typed-errors rule.
        case error(String)
    }

    /// One `label percent reset` run of the Vibe-style line.
    struct Segment: Equatable {
        let kind: UsageWindow.Kind
        /// The window's real length, not its type: "5h", "7d", "30d"; a
        /// per-model window is the model's name; credits is "Cr".
        let label: String
        /// "42%" following `DisplayMode`, or "—" for a slot with no window.
        let percent: String
        /// 0–1, the *displayed* figure, so a bar never contradicts its
        /// number. 0 for a missing window.
        let fraction: Double
        /// The bare countdown ("2h 58m") or clock time ("7:59 PM"), per
        /// `ResetStyle`; a credits slot shows "$14.27 of $25.00" instead
        /// when `showCreditsAmount` is on; nil when there is nothing to say.
        let reset: String?
        let tint: Tint
        /// "Session: 42% used, resets in 2h 58m" — the spoken form.
        let accessibilityLabel: String
    }

    struct Account: Equatable, Identifiable {
        let id: String
        let name: String
        let icon: AccountIcon?
        let planName: String?
        /// `WindowSlots` order: session, weekly, then the per-model window
        /// or the credits fallback — same third-slot rule as the Dashboard.
        let segments: [Segment]
        let status: Status
        let isRefreshing: Bool
        let accessibilityLabel: String
    }

    /// What the two wings beside the notch show while collapsed: the
    /// primary account's chosen metrics, compact labels, no reset.
    struct Collapsed: Equatable {
        let left: [Segment]
        let right: [Segment]
    }

    /// One connected account as the island reads it — the subset of
    /// `UsageModel.AccountUsage` the model needs, so the model stays pure.
    struct AccountInput {
        var account: ConnectedAccount
        var snapshot: UsageSnapshot?
        var needsReauthentication = false
        var isOffline = false
        var lastError: String?
        var isRefreshing = false
    }

    static let maxMetrics = 3
    /// A model name longer than this is cut in the wings — the full name
    /// stays in the expanded line and the accessibility label.
    static let collapsedLabelLimit = 6
    /// Below this length a window is labelled in hours ("5h"), from it on
    /// in days ("7d", "30d").
    static let hoursLabelLimit: TimeInterval = 48 * 3600

    let accounts: [Account]
    /// The account the wings read: the preferred one when still
    /// connected, else the first (`UsageModel.primaryAccountUsage`'s rule).
    let primaryID: String?
    /// From the primary account; empty wings when nothing is connected,
    /// which the view renders as a "Connect" affordance.
    let collapsed: Collapsed
    /// "Claude reports an incident: …" while the provider's status page
    /// reports one, nil on a normal day.
    let incident: String?
    /// Always carries every account's full values, with the account's
    /// nickname in front once two or more are connected (the same
    /// convention the notifications use).
    let accessibilityLabel: String

    init(
        accounts inputs: [AccountInput],
        primaryID: String?,
        displayMode: DisplayMode,
        resetStyle: ResetStyle,
        modelSlotFallback: ModelSlotFallback,
        showCreditsAmount: Bool,
        metrics: [UsageWindow.Kind],
        glanceMetric: UsageWindow.Kind,
        layout: NotchIslandLayout,
        incident: String?,
        now: Date = Date()
    ) {
        let several = inputs.count > 1
        accounts = inputs.map { input in
            let slots = WindowSlots(snapshot: input.snapshot, modelSlotFallback: modelSlotFallback).slots
            let segments = slots.map { slot in
                Self.segment(
                    kind: slot.kind, window: slot.window, snapshot: input.snapshot, compact: false,
                    displayMode: displayMode, resetStyle: resetStyle, showCreditsAmount: showCreditsAmount, now: now
                )
            }
            let status = Self.status(of: input, now: now)
            var spoken = segments.map(\.accessibilityLabel).joined(separator: ", ")
            if spoken.isEmpty { spoken = String(localized: "AIMeter — no usage data yet") }
            if several { spoken = "\(input.account.displayName) — \(spoken)" }
            return Account(
                id: input.account.accountID,
                name: input.account.displayName,
                icon: input.account.icon,
                planName: input.snapshot?.planName,
                segments: segments,
                status: status,
                isRefreshing: input.isRefreshing,
                accessibilityLabel: spoken
            )
        }

        let primary = inputs.first { $0.account.accountID == primaryID } ?? inputs.first
        self.primaryID = primary?.account.accountID
        collapsed = Self.collapsed(
            for: primary, displayMode: displayMode, resetStyle: resetStyle, modelSlotFallback: modelSlotFallback,
            showCreditsAmount: showCreditsAmount, metrics: metrics, glanceMetric: glanceMetric, layout: layout, now: now
        )
        self.incident = incident
        accessibilityLabel = accounts.isEmpty
            ? String(localized: "AIMeter — no usage data yet")
            : accounts.map(\.accessibilityLabel).joined(separator: "; ")
    }

    var primaryAccount: Account? {
        accounts.first { $0.id == primaryID }
    }

    // MARK: - Rules

    /// The wings: `metrics` filtered to what the primary account reports
    /// (the same live-options rule as `menuBarMetrics`), capped at three,
    /// falling back to `glanceMetric` when none applies; then split by
    /// `layout`. A missing primary (no accounts) leaves both wings empty.
    private static func collapsed(
        for primary: AccountInput?, displayMode: DisplayMode, resetStyle: ResetStyle,
        modelSlotFallback: ModelSlotFallback, showCreditsAmount: Bool, metrics: [UsageWindow.Kind],
        glanceMetric: UsageWindow.Kind, layout: NotchIslandLayout, now: Date
    ) -> Collapsed {
        guard let primary else { return Collapsed(left: [], right: []) }
        let available = UsageSnapshot.glanceOptions(for: primary.snapshot, modelSlotFallback: modelSlotFallback)
        let chosen = Array(metrics.filter(available.contains).prefix(maxMetrics))
        let kinds = chosen.isEmpty ? [glanceMetric] : chosen
        let segments = kinds.map { kind in
            segment(
                kind: kind, window: primary.snapshot?.window(for: kind), snapshot: primary.snapshot, compact: true,
                displayMode: displayMode, resetStyle: resetStyle, showCreditsAmount: showCreditsAmount, now: now
            )
        }
        switch layout {
        case .bothSides: return Collapsed(left: Array(segments.prefix(1)), right: Array(segments.dropFirst()))
        case .leftOnly: return Collapsed(left: segments, right: [])
        case .rightOnly: return Collapsed(left: [], right: segments)
        }
    }

    private static func segment(
        kind: UsageWindow.Kind, window: UsageWindow?, snapshot: UsageSnapshot?, compact: Bool,
        displayMode: DisplayMode, resetStyle: ResetStyle, showCreditsAmount: Bool, now: Date
    ) -> Segment {
        // An empty slot still needs its length for the label; a placeholder
        // window yields the kind's default through the public seam.
        let duration = (window ?? UsageWindow(kind: kind, usedPct: 0)).effectiveDuration
        let label = label(for: kind, duration: duration, compact: compact)
        guard let window else {
            return Segment(
                kind: kind, label: label, percent: String(localized: "—"), fraction: 0, reset: nil, tint: .normal,
                accessibilityLabel: String(localized: "\(kind.shortName): no data")
            )
        }
        let shown = window.displayedPct(displayMode)
        let percent = "\(Int(shown))%"
        let danger = window.severity == .critical || window.severity == .exceeded || window.usedPct >= 80
        var spoken = String(localized: "\(kind.shortName): \(Int(shown))% \(displayMode.label)")

        // The wings show only the figure (no room, and no clock to tick it);
        // the spoken label keeps the reset either way.
        var reset: String?
        if let resetsAt = window.resetsAt, resetsAt > now {
            reset = compact ? nil : resetValue(for: resetsAt, style: resetStyle, now: now)
            spoken += ", " + UsageFormatting.resetLabel(for: resetsAt, style: resetStyle, now: now)
        } else if kind == .credits, showCreditsAmount, let amount = snapshot?.spend?.amountLabel {
            reset = compact ? nil : amount
            spoken += ", " + amount
        }
        return Segment(
            kind: kind, label: label, percent: percent, fraction: min(max(shown / 100, 0), 1), reset: reset,
            tint: danger ? .danger : .normal, accessibilityLabel: spoken
        )
    }

    /// The window's length, not its type: under 48 h in hours, from there
    /// on in days — so a provider whose "week" is a month reads "30d"
    /// without a new `Kind`. Per-model windows carry the model's name
    /// (cut to `collapsedLabelLimit` in the wings); credits has no length.
    static func label(for kind: UsageWindow.Kind, duration: TimeInterval?, compact: Bool) -> String {
        switch kind {
        case .modelSpecific(let model):
            return compact ? String(model.prefix(collapsedLabelLimit)) : model
        case .credits:
            return String(localized: "Cr")
        case .session, .weekly:
            guard let duration, duration > 0 else { return kind.shortName }
            if duration < hoursLabelLimit {
                return String(localized: "\(Int((duration / 3600).rounded()))h")
            }
            return String(localized: "\(Int((duration / 86_400).rounded()))d")
        }
    }

    /// The bare value the line shows after the percentage: the countdown
    /// for the relative style, the clock time (with the weekday when not
    /// today) for the absolute one. The full "Resets in …" sentence stays
    /// in the accessibility label.
    static func resetValue(for date: Date, style: ResetStyle, now: Date) -> String {
        switch style {
        case .relative:
            return UsageFormatting.relativeString(from: now, to: date)
        case .absolute:
            let time = date.formatted(date: .omitted, time: .shortened)
            if Calendar.current.isDate(date, inSameDayAs: now) { return time }
            return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
        }
    }

    private static func status(of input: AccountInput, now: Date) -> Status {
        if input.needsReauthentication { return .reauth }
        if input.isOffline { return .offline }
        if let error = input.lastError { return .error(error) }
        if let fetchedAt = input.snapshot?.fetchedAt, now.timeIntervalSince(fetchedAt) > AppConfig.staleAfter {
            return .stale(UsageFormatting.updatedLabel(fetchedAt, now: now))
        }
        return .fresh
    }
}
