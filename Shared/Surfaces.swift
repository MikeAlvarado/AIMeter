import SwiftUI

/// The app's backdrop: Claude's warm ivory (warm charcoal in dark) easing a
/// shade deeper towards the bottom, with a faint terracotta glow at the top
/// edge, so cards have something to float over without the screen reading
/// as a gradient. Every app screen draws it behind its content; widgets keep
/// the flat `Theme.background`, which is its middle tone.
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Theme.backgroundTop, Theme.background, Theme.backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            // Wider than tall and anchored past the top-right corner: a
            // warmth in the light, never a visible spot.
            EllipticalGradient(
                colors: [Theme.accent.opacity(0.045), Theme.accent.opacity(0)],
                center: UnitPoint(x: 0.8, y: -0.05),
                startRadiusFraction: 0,
                endRadiusFraction: 0.75
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// The app's backdrop behind this view (`AppBackground`).
    func appBackground() -> some View {
        background { AppBackground() }
    }

    /// A card's surface: Liquid Glass tinted with the card color on iOS and
    /// macOS 26 and later; before that (and on the Watch) the solid card
    /// with a light along its top edge and a two-layer shadow, which is the
    /// same pane without the glass.
    func cardSurface(radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(CardSurface(radius: radius))
    }

    /// A floating control's surface (the Dashboard's round buttons, "Add
    /// account", the popover's footer button): interactive Liquid Glass on
    /// 26 and later, a thin material with an edge light before.
    func glassControl<S: InsettableShape>(in shape: S) -> some View {
        modifier(GlassControl(shape: shape))
    }
}

private struct CardSurface: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if os(iOS) || os(macOS)
        if #available(iOS 26, macOS 26, *) {
            content
                .glassEffect(.regular.tint(Theme.card.opacity(scheme == .dark ? 0.62 : 0.78)), in: shape)
                .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.05), radius: 18, x: 0, y: 10)
        } else {
            solid(content, shape: shape)
        }
        #else
        solid(content, shape: shape)
        #endif
    }

    private func solid(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(Theme.card, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Theme.edgeLight(scheme), Theme.edgeLight(scheme).opacity(0), Theme.edgeShade(scheme)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.07), radius: 20, x: 0, y: 10)
            .shadow(color: .black.opacity(scheme == .dark ? 0.20 : 0.04), radius: 2, x: 0, y: 1)
    }
}

private struct GlassControl<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        #if os(iOS) || os(macOS)
        if #available(iOS 26, macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            material(content)
        }
        #else
        material(content)
        #endif
    }

    private func material(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay { shape.strokeBorder(Theme.edgeLight(scheme).opacity(0.6), lineWidth: 0.5) }
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.08), radius: 10, x: 0, y: 4)
    }
}
