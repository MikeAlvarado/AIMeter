import Foundation

/// Anthropic's weekday peak-usage window for Claude's 5-hour session
/// limit — **retired**. `current` is nil, which switches off every peak
/// surface at once (Provider Detail's card, the menu bar and widget
/// badges, the Live Activity bolt, the `peak.` notification family and
/// its Settings toggle) while keeping the whole mechanism in place —
/// `PeakCalculator`, `ClaudePeakStatus`, the badge views, the widget
/// timelines' transition entry, `reschedulePeakNotifications` — so
/// bringing it back is one line: assign `lastKnown` (with fresh hours and
/// a fresh `lastVerified`) to `current`.
///
/// Why it was retired (2026-09-22): the policy no longer exists. Anthropic
/// introduced the 5–11 AM PT weekday reduction in March 2026 for Claude
/// Code on Pro and Max, and announced its removal on 2026-05-06 ("removing
/// the peak hours limit reduction on Claude Code for Pro and Max
/// accounts", anthropic.com/news/higher-limits-spacex). No Anthropic help
/// page — Pro, Max, Team, or "Usage limit best practices" — describes a
/// peak window for any plan since, and Team/Enterprise never had one
/// documented (Team Premium seats launched in late April, after the
/// policy, and the removal note names only the plans it had applied to).
/// The "back again" this schedule was re-verified against on 2026-08-03
/// came from a scheduler warning, not documentation, and that day's own
/// captures (`docs/design/peak-hours-investigation.md`) found nothing in
/// the endpoint either — the same absence of a server-side signal that
/// forced the schedule to be hardcoded in the first place also means the
/// app has no way to notice on its own when the policy stops applying,
/// so a stale schedule silently keeps announcing "Peak hours now" every
/// weekday morning to users whose limits no longer change. That is worse
/// than showing nothing, hence nil rather than an updated date.
public enum ClaudePeakSchedule {
    /// The schedule every peak surface reads. Nil means "no peak policy
    /// in force": `ClaudePeakStatus` reports off-peak with no next
    /// transition, the timelines add no transition entry, and the
    /// notification family only clears any pending requests an older
    /// build scheduled.
    public static let current: PeakCalculator.Schedule? = nil

    /// The policy as it last stood, kept for the day it returns — verify
    /// the hours and update `lastVerified` before reassigning it to
    /// `current`.
    public static let lastKnown = PeakCalculator.Schedule(
        timeZoneIdentifier: "America/Los_Angeles",
        weekdays: [2, 3, 4, 5, 6], // Calendar weekday: Monday...Friday
        startHour: 5,
        endHour: 11,
        lastVerified: verifiedDate(year: 2026, month: 8, day: 3)
    )

    private static func verifiedDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
