import Foundation
import UsageKit

/// Fixed three-slot presentation used across dashboard, detail, and
/// widgets: session, weekly, top model — always visible; a missing window
/// keeps its slot so the composition never shifts.
struct WindowSlots {
    let slots: [(kind: UsageWindow.Kind, window: UsageWindow?)]

    init(snapshot: UsageSnapshot?) {
        let model = snapshot?.modelWindows.first
        slots = [
            (.session, snapshot?.sessionWindow),
            (.weekly, snapshot?.weeklyWindow),
            (model?.kind ?? .modelSpecific("Fable"), model),
        ]
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
