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
/// account's spend/credit status instead of a dead placeholder.
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
