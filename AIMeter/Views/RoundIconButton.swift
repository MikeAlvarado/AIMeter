import SwiftUI

/// Floating circular icon button (dashboard header). While busy, the icon
/// plays exactly one full rotation as feedback that a refresh started.
///
/// The spin is a single fixed-duration animation, not tied to how long the
/// actual fetch takes — most refreshes finish well under a second, so
/// animating continuously until `isBusy` goes false (via `TimelineView` or
/// `repeatForever`) gets cut off mid-turn far more often than not, which
/// reads as a stutter rather than a spin. Firing one clean 360° turn on
/// the rising edge of `isBusy` always completes, and a one-shot animation
/// has no repeating object that can leak or stack on a second tap — the
/// bug class that made the previous approach stick.
struct RoundIconButton: View {
    let systemName: String
    var isBusy = false
    let action: () -> Void
    @State private var rotation = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.ink)
                .rotationEffect(.degrees(rotation))
                .frame(width: 40, height: 40)
                .background(Theme.card, in: Circle())
                .shadow(color: Theme.shadowSoft, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onChange(of: isBusy) { wasBusy, busy in
            guard busy, !wasBusy else { return }
            // Reduce Motion: still land on the same +360° value (so state
            // stays consistent across repeated taps) but skip animating the
            // turn — the haptic in DashboardView already confirms the tap.
            if reduceMotion {
                rotation += 360
            } else {
                withAnimation(.easeInOut(duration: 0.5)) {
                    rotation += 360
                }
            }
        }
    }
}
