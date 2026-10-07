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
            Text(planName.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Theme.track.opacity(0.7), in: Capsule())
        }
    }
}
