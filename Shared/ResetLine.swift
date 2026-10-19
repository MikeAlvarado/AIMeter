import SwiftUI

/// What a widget's reset line shows for one window: a countdown the
/// system ticks on its own, or a fixed label.
///
/// A widget is drawn once per timeline entry, so "Resets in 2h 23m" was
/// a photograph of the minute it was drawn, up to a cadence old. A
/// `Text(timerInterval:)` is live: WidgetKit redraws it every second
/// with no entry and no budget. It is worth it only under a day (above
/// that the count of hours would have no meaning next to "2d"), and
/// only for the relative style, since "Resets at 7:59 PM" is a fixed
/// time already. A reset already past gets the label (the timer would
/// sit at 0:00), which is what the next reload replaces.
enum ResetLine: Equatable {
    /// `Text(timerInterval:)` over this range: "2:23:05", then "59:59".
    case countdown(ClosedRange<Date>)
    /// "Resets in 2d 22h" / "Resets at 7:59 PM" (`UsageFormatting.resetLabel`).
    case label(String)

    /// The longest reset a countdown is shown for.
    static let countdownLimit: TimeInterval = 24 * 3600

    static func line(for resetsAt: Date, style: ResetStyle, now: Date) -> ResetLine {
        let remaining = resetsAt.timeIntervalSince(now)
        if style == .relative, remaining > 0, remaining < countdownLimit {
            return .countdown(now...resetsAt)
        }
        return .label(UsageFormatting.resetLabel(for: resetsAt, style: style, now: now))
    }
}

/// The reset line's text: the live countdown or the label, in the
/// caller's font. `now` is the entry's date, never `Date()`: an entry is
/// drawn ahead of its time, and the range is the entry's to keep. `bare`
/// drops the sentence for a line with no room for it: "2:23:05", "2d
/// 22h", "7:59 PM" (`UsageFormatting.resetValue`).
struct ResetLineText: View {
    let resetsAt: Date
    let style: ResetStyle
    let now: Date
    var bare = false

    var body: some View {
        switch ResetLine.line(for: resetsAt, style: style, now: now) {
        case .countdown(let range):
            if bare {
                Text(timerInterval: range, countsDown: true)
                    .monospacedDigit()
            } else {
                Text("Resets in \(Text(timerInterval: range, countsDown: true))")
                    .monospacedDigit()
            }
        case .label(let text):
            Text(bare ? UsageFormatting.resetValue(for: resetsAt, style: style, now: now) : text)
        }
    }
}
