import Foundation

/// Anthropic's documented weekday peak-usage window for Claude's 5-hour
/// session limit: usage burns roughly 2x faster 5:00-11:00 AM PT on
/// weekdays; weekends are fully off-peak. This policy has changed more
/// than once in 2026 (introduced ~March, reverted 2026-05-06, back again
/// by the date below) with no server-side signal to key off instead of a
/// hardcoded schedule — confirmed by diffing a live peak-window response
/// against an off-peak one; see `docs/design/peak-hours-investigation.md`.
///
/// `lastVerified` is the honesty mechanism for that volatility: it's
/// surfaced in the UI next to the peak indicator so a schedule that goes
/// stale between app releases is never presented as live truth. Update
/// both the schedule and this date together whenever the policy is
/// re-confirmed or changes again.
public enum ClaudePeakSchedule {
    public static let current = PeakCalculator.Schedule(
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
