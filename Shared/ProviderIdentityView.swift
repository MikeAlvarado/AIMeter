import SwiftUI

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

    var body: some View {
        Image("ClaudeIcon")
            .resizable()
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
        Text(name)
            .font(font)
            .foregroundStyle(nameColor)
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
