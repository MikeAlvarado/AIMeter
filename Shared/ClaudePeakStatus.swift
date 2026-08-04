import Foundation
import UsageKit

/// Claude's peak-hours indicator, computed live from `ClaudePeakSchedule`
/// — no network call, since peak state is a pure function of time (see
/// `docs/design/peak-hours-investigation.md` for why nothing else is
/// available to key off). Shared by Provider Detail, the macOS menu bar,
/// and both widget headers so the same schedule and copy back every
/// surface.
struct ClaudePeakStatus {
    let isPeak: Bool
    let nextTransition: Date?
    let lastVerified: Date
    private let referenceDate: Date

    init(at date: Date = Date(), schedule: PeakCalculator.Schedule = ClaudePeakSchedule.current) {
        referenceDate = date
        isPeak = PeakCalculator.isPeak(at: date, schedule: schedule)
        nextTransition = PeakCalculator.nextTransition(after: date, schedule: schedule)
        lastVerified = schedule.lastVerified
    }

    var title: String {
        isPeak ? String(localized: "Peak hours now") : String(localized: "Off-peak now")
    }

    /// "Session usage may burn faster · off-peak in 2h 10m" / "Next peak in 20h 5m".
    var subtitle: String {
        guard let nextTransition else { return "" }
        let until = UsageFormatting.relativeString(from: referenceDate, to: nextTransition)
        return isPeak
            ? String(localized: "Session usage may burn faster · off-peak in \(until)")
            : String(localized: "Next peak in \(until)")
    }

    /// Static description of the documented schedule, independent of
    /// whether it's currently active — for a footnote alongside the
    /// live status.
    var scheduleDescription: String {
        String(localized: "Weekdays 5-11 AM PT, Claude session usage may burn faster.")
    }

    var lastVerifiedLabel: String {
        String(localized: "Schedule as of \(lastVerified.formatted(date: .abbreviated, time: .omitted)).")
    }
}
