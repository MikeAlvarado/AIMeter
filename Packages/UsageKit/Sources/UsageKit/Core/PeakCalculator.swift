import Foundation

/// Whether `now` falls inside a recurring, named-timezone peak window —
/// e.g. Anthropic's documented weekday-morning peak-usage policy for
/// Claude's session limit (see `docs/design/peak-hours-investigation.md`
/// for how this was confirmed to have no server-side signal to key off
/// instead). Pure and provider-agnostic: the *mechanism* is generic — a
/// weekday+hour range evaluated in a fixed timezone, independent of the
/// device's own timezone — while the concrete schedule value is supplied
/// by the caller (see `ClaudePeakSchedule` for Anthropic's).
public enum PeakCalculator {
    /// A recurring window defined in a named timezone's wall-clock time.
    /// Critically, `timeZoneIdentifier` — never the device's current
    /// timezone — is what the weekday/hour check runs against, so the
    /// result is identical no matter where the device itself is.
    public struct Schedule: Equatable, Sendable {
        /// e.g. "America/Los_Angeles". A named identifier carries the tz
        /// database's own historical and future DST rules; never hardcode
        /// a fixed UTC offset here, or every DST transition breaks it.
        public let timeZoneIdentifier: String
        /// `Calendar` weekday integers (Sunday = 1 ... Saturday = 7).
        public let weekdays: Set<Int>
        /// Local hour the window opens, inclusive.
        public let startHour: Int
        /// Local hour the window closes, exclusive.
        public let endHour: Int
        /// When this schedule was last confirmed against reality. Shown
        /// in the UI so a hardcoded, occasionally-stale schedule is never
        /// presented as live server truth.
        public let lastVerified: Date

        public init(
            timeZoneIdentifier: String,
            weekdays: Set<Int>,
            startHour: Int,
            endHour: Int,
            lastVerified: Date
        ) {
            self.timeZoneIdentifier = timeZoneIdentifier
            self.weekdays = weekdays
            self.startHour = startHour
            self.endHour = endHour
            self.lastVerified = lastVerified
        }

        var timeZone: TimeZone {
            TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "GMT")!
        }
    }

    /// Whether `date` falls inside the schedule's recurring window,
    /// evaluated in the schedule's own timezone — never the caller's
    /// `Calendar.current`/`TimeZone.current`, which must have zero
    /// influence on the result.
    public static func isPeak(at date: Date = Date(), schedule: Schedule) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = schedule.timeZone
        let components = calendar.dateComponents([.weekday, .hour], from: date)
        guard let weekday = components.weekday, let hour = components.hour else { return false }
        return schedule.weekdays.contains(weekday) && hour >= schedule.startHour && hour < schedule.endHour
    }

    /// The next moment `isPeak` flips (into or out of the window) after
    /// `date` — feeds a future "peak started/ended" notification. Scans
    /// forward hour by hour in the schedule's timezone, which is exact
    /// (the schedule only ever changes on whole local hours) and always
    /// terminates well within the loop's cap, since a peak or off-peak
    /// span never exceeds a few days (the weekend gap). `nil` only for a
    /// degenerate schedule (no weekdays, or a zero/negative-width window).
    public static func nextTransition(after date: Date = Date(), schedule: Schedule) -> Date? {
        guard !schedule.weekdays.isEmpty, schedule.endHour > schedule.startHour else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = schedule.timeZone

        let currentlyPeak = isPeak(at: date, schedule: schedule)
        let currentHour = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard var probe = calendar.date(from: currentHour) else { return nil }

        for _ in 0..<(24 * 8) {
            guard let next = calendar.date(byAdding: .hour, value: 1, to: probe) else { return nil }
            probe = next
            if isPeak(at: probe, schedule: schedule) != currentlyPeak {
                return probe
            }
        }
        return nil
    }
}
