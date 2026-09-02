import SwiftUI

/// The glyph that stands in for a provider wherever a header reads
/// "icon + name": `ProviderIdentityView` (dashboard, landscape, menu bar,
/// every widget), the Connect sheet header, Privacy & data, and the Live
/// Activity's compact/minimal islands.
///
/// Deliberately an SF Symbol on the app's own accent wash, *not* the
/// provider's logo. Anthropic's trademark guidelines reserve the Claude
/// logo for uses it has approved in writing, and App Review (guidelines
/// 4.1(c) and 5.2.1) treats a third party's icon the same way; the app was
/// rejected once over brand use. The provider is identified by its name
/// alone — plain-text, referential use, which is what both actually permit.
/// Nothing in the bundle should draw a third party's mark.
struct ProviderMark: View {
    let size: CGFloat
    let cornerRadius: CGFloat
    /// Filled tile with a white glyph for a sheet-sized header; every inline
    /// header uses the quieter wash + accent glyph the rest of the app's
    /// icon tiles already use (Settings rows, Privacy rows).
    var prominent: Bool = false

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Theme.accent)
            .frame(width: size, height: size)
            .background(
                prominent ? Theme.accent : Theme.accentWash,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
