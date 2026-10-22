import SwiftUI
import UsageKit

/// Icon + name + optional plan pill — the repeated first part of every
/// provider header across the dashboard, landscape view, menu bar, and
/// widgets. Each caller wraps it in its own `HStack` with whatever
/// trailing content and spacing that surface needs (chevron, "Updated X
/// ago", a staleness hint, or nothing), since those genuinely differ per
/// surface; the icon/name/pill trio doesn't.
struct ProviderIdentityView: View {
    let name: String
    let iconSize: CGFloat
    let iconCornerRadius: CGFloat
    let font: Font
    let nameColor: Color
    let planName: String?
    /// The account's chosen glyph (`ConnectedAccount.icon`); nil is the
    /// default mark.
    var icon: AccountIcon? = nil
    /// A smaller pill for a header with little height (the Watch's list
    /// sections): the phone's reads as tall as its row there.
    var compactPill = false

    var body: some View {
        ProviderMark(size: iconSize, cornerRadius: iconCornerRadius, icon: icon)
        Text(name)
            .font(font)
            .foregroundStyle(nameColor)
            // A header name never wraps: the small widget has ~126 pt for
            // icon, name and window label, and "Personal" split across two
            // lines read as a bug. Truncation with an ellipsis is the
            // honest fallback for a long nickname, after shrinking a little.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        if let planName {
            PlanPill(name: planName, compact: compactPill)
        }
    }
}

/// The plan pill beside an account's name ("Pro", "Max"): drawn here and
/// in Settings' account rows, which put it beside the name over a second
/// line of their own.
struct PlanPill: View {
    let name: String
    var compact = false

    var body: some View {
        Text(name.capitalized)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, compact ? 1.5 : 3)
            .background(Theme.track.opacity(0.7), in: Capsule())
    }
}
