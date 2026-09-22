import SwiftUI

/// The one peak-hours glyph every glance surface shares — a bolt in
/// `Theme.danger`, optionally with the status title beside it. Callers
/// decide *whether* to show it (`ClaudePeakStatus.isPeak`, or the Live
/// Activity's `isPeak` state); this only decides what it looks like, so
/// the menu bar popover, both widget headers, the all-accounts widget and
/// the Live Activity can't drift apart. Never shown while the policy is
/// retired (`ClaudePeakSchedule.current` is nil), since nothing reports
/// `isPeak` then.
struct PeakBadge: View {
    var size: CGFloat = 9
    var title: String? = nil
    var titleFont: Font = .system(size: 11, weight: .semibold)

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: size))
                .foregroundStyle(Theme.danger)
            if let title {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}
