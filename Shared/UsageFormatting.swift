import Foundation
import UsageKit

/// Fixed three-slot presentation used across dashboard, detail, and
/// widgets: session, weekly, top model — always visible; a missing window
/// keeps its slot so the composition never shifts.
///
/// The third slot only ever shows a real per-model window when the plan
/// actually reports one (e.g. Max/Team Premium's Fable 5 allowance). When it
/// doesn't — most Claude Pro accounts, since Fable moved to usage credits —
/// `modelSlotFallback` decides what happens: `.hidden` drops the slot
/// entirely (two rows), `.credits` keeps three rows and fills it with the
/// account's spend/credit status instead of a dead placeholder, and `.auto`
/// (the default) picks between those two by itself — the row appears
/// exactly when the account's spend/credits status is enabled.
struct WindowSlots {
    let slots: [(kind: UsageWindow.Kind, window: UsageWindow?)]

    init(snapshot: UsageSnapshot?, modelSlotFallback: ModelSlotFallback) {
        let model = snapshot?.modelWindows.first
        var built: [(kind: UsageWindow.Kind, window: UsageWindow?)] = [
            (.session, snapshot?.sessionWindow),
            (.weekly, snapshot?.weeklyWindow),
        ]
        if let model {
            built.append((model.kind, model))
        } else {
            switch modelSlotFallback {
            case .hidden:
                break
            case .credits:
                built.append((.credits, snapshot?.creditsWindow))
            case .auto:
                if let creditsWindow = snapshot?.creditsWindow {
                    built.append((.credits, creditsWindow))
                }
            }
        }
        slots = built
    }

    /// Whether the slot at `index` should render its reset line.
    /// Consecutive windows sharing one reset date (Weekly and
    /// Weekly·Fable) show it once, under the last of the group — every
    /// surface applies the same rule.
    static func showsReset(
        at index: Int,
        in slots: [(kind: UsageWindow.Kind, window: UsageWindow?)]
    ) -> Bool {
        guard let reset = slots[index].window?.resetsAt else { return false }
        guard index + 1 < slots.count else { return true }
        return slots[index + 1].window?.resetsAt != reset
    }
}

extension UsageSnapshot {
    /// Synthesizes a display-only window from the account's spend cap, for
    /// `WindowSlots`'s `.credits` fallback. Not a provider-reported window
    /// (no `resetsAt` — a spend cap has no rollover boundary) and never
    /// saved back into `windows`. `spend` over `extraUsage`: only `spend`
    /// carries a `severity`, which is what `UsageWindow.tint` keys off.
    var creditsWindow: UsageWindow? {
        guard let spend, spend.enabled, let percent = spend.percent else { return nil }
        return UsageWindow(kind: .credits, usedPct: percent, severity: spend.severity)
    }

    /// Resolves the one window a `glanceMetric` preference points at, for
    /// the macOS menu bar label and iOS's Lock Screen circular gauge —
    /// both single-number surfaces with no room for a fixed three-slot
    /// layout. Missing data (e.g. Credits picked but spend disabled, or a
    /// per-model window from a plan the account no longer has) renders as
    /// the surface's own placeholder, same as any other slot.
    func window(for kind: UsageWindow.Kind) -> UsageWindow? {
        switch kind {
        case .session: return sessionWindow
        case .weekly: return weeklyWindow
        case .modelSpecific: return modelWindows.first { $0.kind == kind }
        case .credits: return creditsWindow
        }
    }

    /// The window kinds this account currently reports, for pickers that
    /// need a live list instead of a hardcoded one — session and weekly
    /// are always offered; the per-model window (e.g. Fable on Max) is
    /// offered whenever the account has one; Credits only when the
    /// account has it enabled *and* the user hasn't turned the third-row
    /// fallback fully off — the same `modelSlotFallback` rule
    /// `UsageWindowOptionQuery` applies for the single-window widget, so
    /// setting "Third usage row" to Hidden also removes Credits from this
    /// picker's options.
    static func glanceOptions(for snapshot: UsageSnapshot?, modelSlotFallback: ModelSlotFallback) -> [UsageWindow.Kind] {
        var kinds: [UsageWindow.Kind] = [.session, .weekly]
        if let model = snapshot?.modelWindows.first {
            kinds.append(model.kind)
        }
        if modelSlotFallback != .hidden, snapshot?.creditsWindow != nil {
            kinds.append(.credits)
        }
        return kinds
    }
}

extension Preferences {
    /// The Credits row's optional "$14.27 of $25.00" subtitle, shared by
    /// every surface that renders `WindowSlots`'s credits slot (dashboard,
    /// provider detail, menu bar, widgets) — nil unless the slot actually
    /// is Credits, the toggle is on, and the account has spend data.
    func creditsAmountSubtitle(for kind: UsageWindow.Kind, snapshot: UsageSnapshot?) -> String? {
        guard kind == .credits, showCreditsAmount else { return nil }
        return snapshot?.spend?.amountLabel
    }
}

extension PreferencesModel {
    /// Same rule as `Preferences.creditsAmountSubtitle`, for call sites
    /// (the app's own views) that hold the observable model instead of a
    /// plain `Preferences` value.
    func creditsAmountSubtitle(for kind: UsageWindow.Kind, snapshot usageSnapshot: UsageSnapshot?) -> String? {
        snapshot.creditsAmountSubtitle(for: kind, snapshot: usageSnapshot)
    }
}

extension SpendStatus {
    /// "$14.27 of $25.00" — the optional money subtitle shown under the
    /// Credits row instead of a reset line, since a spend cap has no
    /// rollover date. Opt-in via `Preferences.showCreditsAmount`.
    var amountLabel: String? {
        guard let used = usedAmount, let limit = limitAmount else { return nil }
        let code = currency ?? "USD"
        let usedText = used.formatted(.currency(code: code))
        let limitText = limit.formatted(.currency(code: code))
        return String(localized: "\(usedText) of \(limitText)")
    }
}

extension UsageWindow {
    /// The value shown for the current display mode (0–100).
    func displayedPct(_ mode: DisplayMode) -> Double {
        mode == .used ? usedPct : remainingPct
    }
}

enum UsageFormatting {
    /// "Resets in 4h 12m" / "Resets in 2d 22h" — or absolute local time:
    /// "Resets at 7:59 PM" (same day) / "Resets Sun 7:59 PM".
    static func resetLabel(for date: Date, style: ResetStyle, now: Date = Date()) -> String {
        switch style {
        case .relative:
            return String(localized: "Resets in \(relativeString(from: now, to: date))")
        case .absolute:
            let time = date.formatted(date: .omitted, time: .shortened)
            if Calendar.current.isDate(date, inSameDayAs: now) {
                return String(localized: "Resets at \(time)")
            }
            let day = date.formatted(.dateTime.weekday(.abbreviated))
            return String(localized: "Resets \(day) \(time)")
        }
    }

    /// Compact two-unit countdown: "4h 12m", "2d 22h", "38m", "now".
    static func relativeString(from now: Date, to date: Date) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24

        if days >= 1 {
            let remainderHours = hours % 24
            return remainderHours > 0 ? "\(days)d \(remainderHours)h" : "\(days)d"
        }
        if hours >= 1 {
            let remainderMinutes = minutes % 60
            return remainderMinutes > 0 ? "\(hours)h \(remainderMinutes)m" : "\(hours)h"
        }
        if minutes >= 1 {
            return "\(minutes)m"
        }
        return String(localized: "now")
    }

    /// "Updated 2 min ago" footer text.
    static func updatedLabel(_ fetchedAt: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(fetchedAt))
        if seconds < 60 {
            return String(localized: "Updated just now")
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return String(localized: "Updated \(minutes) min ago")
        }
        let hours = minutes / 60
        if hours < 24 {
            return String(localized: "Updated \(hours)h ago")
        }
        return String(localized: "Updated \(hours / 24)d ago")
    }
}
