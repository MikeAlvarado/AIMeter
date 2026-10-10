#if os(macOS)
import SwiftUI
import UsageKit

/// The slab's frame in the hosting view's coordinates, reported so hit
/// testing can be confined to it (`NotchIslandHostingView.slab`).
private struct SlabFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// The island's whole SwiftUI tree, built the way boring.notch builds
/// its notch: the window is fixed and never resizes, and the black slab
/// is simply the *natural size of its content* — the bare notch, the
/// wings row, or the row with the body under it — so a level change is
/// one layout change that one spring animates, radii, shadow and all.
/// No measurements go up to the controller and no frames come down:
/// the view owns the motion, the controller owns the level. Drawn in
/// dark `colorScheme` by the controller, so every `Theme` color here is
/// its dark variant on black.
struct NotchIslandRoot: View {
    let state: NotchIslandState
    let actions: NotchIslandActions
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var now = Date()

    /// Inset around the reveal caption.
    static let captionPadding: CGFloat = 16
    static let rootSpace = "notch-island-root"

    var body: some View {
        slab(now: now)
            .padding(.bottom, NotchIslandGeometry.shadowPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: .notchCenter, vertical: .top))
            // The root fills the hosting view, so this space is its bounds
            // — what `NotchIslandHostingView.slab` is compared against.
            .coordinateSpace(name: Self.rootSpace)
            // Relative resets tick while open — the one clock the island
            // ever runs, and a sleep rather than a `TimelineView`: swapping
            // the slab in and out of one would change its identity at the
            // very moment it animates.
            .task(id: state.level > .collapsed) {
                guard state.level > .collapsed else { return }
                now = Date()
                while !Task.isCancelled {
                    let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime)
                        ?? Date().addingTimeInterval(60)
                    try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
                    guard !Task.isCancelled else { return }
                    now = Date()
                }
            }
    }

    // MARK: - Slab

    private func slab(now: Date) -> some View {
        let island = NotchIslandModel.current(model: model, prefs: prefs, now: now)
        let open = state.level > .collapsed
        let expanded = state.level == .expanded
        return VStack(alignment: .notchCenter, spacing: 0) {
            header(island: island)
                .zIndex(2)
            if state.level == .peek, state.isRevealing {
                revealCaption
                    .transition(bodyTransition)
            }
            if expanded {
                ExpandedContent(island: island, mode: state.mode)
                    .frame(width: NotchIslandGeometry.expandedWidth - 2 * NotchIslandGeometry.Radii.open.top)
                    .transition(bodyTransition)
                    .zIndex(1)
            }
        }
        .notchIslandSurface(
            mode: state.mode,
            radii: expanded ? .open : .closed,
            casts: open || state.isHovering
        )
        .animation(levelAnimation, value: state.level)
        .animation(flapAnimation, value: state.isHovering)
        .contentShape(Rectangle())
        .onHover(perform: actions.hover)
        .onTapGesture(perform: actions.tap)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SlabFrameKey.self, value: proxy.frame(in: .named(Self.rootSpace)))
            }
        }
        .onPreferenceChange(SlabFrameKey.self) { frame in actions.slabChanged(frame) }
    }

    /// The top row: collapsed on a notch Mac it is a clear rect the notch's
    /// size (black on black, invisible, the slab *is* the notch) that
    /// swells by `hoverFlap` while the cursor rests on it; from the peek
    /// on, the wings. The pill has nowhere to hide its row, so it always
    /// shows it.
    @ViewBuilder
    private func header(island: NotchIslandModel) -> some View {
        switch state.mode {
        case .notch(let notch):
            if state.level > .collapsed {
                CollapsedRow(island: island, mode: state.mode, notchWidth: notch.width)
                    .frame(height: state.barHeight)
                    .transition(.opacity.animation(.smooth(duration: 0.25)))
            } else {
                let flap = state.isHovering ? NotchIslandGeometry.hoverFlap : .zero
                Color.clear
                    .frame(
                        width: max(0, state.closedWidth - 2 * NotchIslandGeometry.Radii.closed.top) + flap.width,
                        height: state.barHeight + flap.height
                    )
                    .alignmentGuide(.notchCenter) { $0.width / 2 }
            }
        case .pill:
            CollapsedRow(island: island, mode: state.mode)
                .frame(height: state.barHeight)
        }
    }

    // MARK: - Motion

    /// boring.notch's pair: a touch of overshoot on the way open, none on
    /// the way shut. Nothing under Reduce Motion.
    private var levelAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return state.level > .collapsed
            ? .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
            : .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    }

    /// The hover flap and the shadow: quick, slightly bouncy.
    private var flapAnimation: Animation? {
        reduceMotion ? nil : .interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    }

    /// How the body (and the reveal caption) comes and goes: scaled from
    /// the top and faded, on its own smooth curve, so it reads as
    /// unfolding out of the bar while the slab grows under it.
    private var bodyTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.8, anchor: .top)
            .combined(with: .opacity)
            .animation(.smooth(duration: 0.35))
    }

    /// The first-run caption under the open wings: one line saying what
    /// the island is and how it opens.
    private var revealCaption: some View {
        Text("AIMeter lives in the notch now — rest the cursor here to peek, click to open.")
            .font(.system(size: 11))
            .foregroundStyle(NotchIslandStyle.reset)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: NotchIslandGeometry.expandedWidth - 2 * Self.captionPadding)
            .fixedSize()
            .padding(.horizontal, Self.captionPadding)
            .padding(.top, 2)
            .padding(.bottom, 10)
    }
}

/// The island's type and colors — white at the reference's opacities on
/// pure black, the app's two accent colors (dark variants) for figures.
enum NotchIslandStyle {
    static let label = Color.white.opacity(0.82)
    static let reset = Color.white.opacity(0.5)
    static let separator = Color.white.opacity(0.22)
    static let track = Color.white.opacity(0.14)
    static let hairline = Color.white.opacity(0.08)
    static let control = Color.white.opacity(0.85)

    static func font(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced).monospacedDigit()
    }

    static func tint(_ tint: NotchIslandModel.Tint) -> Color {
        tint == .danger ? Theme.danger : Theme.accent
    }
}

extension NotchIslandModel {
    /// The live island, from the model and the preferences — what the
    /// panel draws and what Settings previews, so the preview is the
    /// truth (the same rule as `MenuBarLabelModel.current`).
    static func current(model: UsageModel, prefs: PreferencesModel, now: Date = Date(), layout: NotchIslandLayout? = nil) -> NotchIslandModel {
        NotchIslandModel(
            accounts: model.accounts.map { usage in
                AccountInput(
                    account: usage.account,
                    snapshot: usage.snapshot,
                    needsReauthentication: usage.needsReauthentication,
                    isOffline: usage.isOffline,
                    lastError: usage.lastError,
                    isRefreshing: usage.isRefreshing
                )
            },
            primaryID: prefs.primaryAccountID,
            displayMode: prefs.displayMode,
            resetStyle: prefs.resetStyle,
            modelSlotFallback: prefs.modelSlotFallback,
            showCreditsAmount: prefs.showCreditsAmount,
            metrics: prefs.notchIslandMetrics,
            glanceMetric: prefs.glanceMetric,
            layout: layout ?? prefs.notchIslandLayout,
            incident: model.activeIncident.map { incident in
                let name = ProviderCatalog.displayName(for: incident.providerID)
                let what = incident.status.incidentTitle ?? incident.status.description
                return String(localized: "\(name) reports an incident: \(what)")
            },
            now: now
        )
    }
}
#endif
