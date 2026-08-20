import SwiftUI
import UsageKit

struct DashboardView: View {
    @Environment(UsageModel.self) private var model
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var showingSettings = false
    @State private var showingConnect = false
    /// The section being dragged, how far it has moved, and which section
    /// it would drop onto — see `accountSection(_:)` for why the reorder
    /// carries this state itself instead of using SwiftUI's drag and drop.
    @State private var draggingID: String?
    @State private var dragTranslation: CGFloat = 0
    @State private var dropTargetID: String?
    /// Each section's on-screen rect, so a drag can tell what it's over.
    @State private var sectionFrames: [String: CGRect] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header
                providerSection
            }
            .padding(20)
        }
        .background(Theme.background)
        // Soft tap when a refresh kicks off — pull gesture or button alike.
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.isRefreshing) { _, isRefreshing in
            isRefreshing
        }
        // And a firmer one the moment a card lifts, which is the only
        // confirmation that the hold registered — the card hasn't moved yet.
        .sensoryFeedback(.impact(weight: .medium), trigger: draggingID) { was, now in
            was == nil && now != nil
        }
        .navigationDestination(for: String.self) { accountID in
            ProviderDetailView(accountID: accountID)
        }
        #if os(iOS)
        .refreshable { await model.refreshAll() }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
        }
        #endif
        .sheet(isPresented: $showingConnect) {
            ConnectClaudeSheet()
        }
    }

    private var header: some View {
        ZStack {
            // Small centered app title — present but never competing with
            // the usage content below.
            Text(verbatim: "AIMeter")
                .font(.system(.headline, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
            HStack {
                headerButtons
            }
        }
    }

    private var headerButtons: some View {
        HStack {
            RoundIconButton(systemName: "gearshape") {
                #if os(macOS)
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
                #else
                showingSettings = true
                #endif
            }
            .accessibilityLabel(Text("Settings"))
            Spacer()
            RoundIconButton(systemName: "arrow.clockwise", isBusy: model.isRefreshing) {
                Task { await model.refreshAll() }
            }
            .accessibilityLabel(Text("Refresh"))
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            if model.needsConnection {
                Card {
                    VStack(spacing: 14) {
                        DisconnectedPrompt(buttonLabel: "Connect", verticalPadding: 12) {
                            showingConnect = true
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(model.accounts) { usage in
                    accountSection(usage)
                }
                addAccountButton
            }
        }
        .coordinateSpace(name: Self.reorderSpace)
        .onPreferenceChange(AccountSectionFramesKey.self) { frames in
            sectionFrames = frames
        }
    }

    /// Sections reorder by hold-and-drag once there's more than one account
    /// (nothing to reorder otherwise, and no reason to put a drag gesture
    /// in the way of the single-account case). Holding a card lifts it,
    /// dragging moves it, and releasing over another section makes it take
    /// that section's place — which rewrites the shared account registry,
    /// so the macOS menu bar popover, the all-accounts widget, and every
    /// account picker pick up the same order.
    ///
    /// Built on a plain gesture rather than SwiftUI's drag and drop
    /// (`.draggable`/`.dropDestination`), and that is the whole reason this
    /// code exists: the system carries a *preview* of the dragged view, and
    /// UIKit scales that preview down to fit its own bounds — a full-width
    /// account card lifts at roughly half size, with nothing on
    /// `.draggable(preview:)` to prevent it (supplying a preview at the
    /// measured on-screen width was tried; it gets scaled just the same).
    /// Here nothing is lifted out at all: the real card stays in the layout
    /// and only takes an `offset`, so it moves at exactly the size it had.
    ///
    /// Resolving on release (rather than reordering live under the finger)
    /// keeps the state down to "which card, moved how far, over what" — and
    /// a gesture, unlike a drag session, always ends, so there is no
    /// cancelled-drag hole to defend against either.
    @ViewBuilder
    private func accountSection(_ usage: UsageModel.AccountUsage) -> some View {
        // Always found: `usage` came from iterating this same array.
        let index = model.accounts.firstIndex { $0.id == usage.id } ?? 0
        let canReorder = model.accounts.count > 1 && !model.isDemoMode
        let isDragging = draggingID == usage.id
        let section = AccountSectionView(
            usage: usage,
            moveUp: canReorder && index > 0 ? { model.moveAccount(usage.id, by: -1) } : nil,
            moveDown: canReorder && index < model.accounts.count - 1 ? { model.moveAccount(usage.id, by: 1) } : nil
        )

        if canReorder {
            section
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: AccountSectionFramesKey.self,
                            value: [usage.id: proxy.frame(in: .named(Self.reorderSpace))]
                        )
                    }
                }
                .overlay { AccountDropHighlight(isTargeted: dropTargetID == usage.id) }
                // Depth instead of scale: a lifted card that also grows is
                // exactly what this interaction was rebuilt to avoid.
                .shadow(color: isDragging ? Theme.shadowSoft : .clear, radius: 22, x: 0, y: 12)
                .offset(y: isDragging ? dragTranslation : 0)
                // Over its neighbours while it travels, back in line after.
                .zIndex(isDragging ? 1 : 0)
                .gesture(reorderGesture(for: usage.id))
        } else {
            section
        }
    }

    /// Hold, then drag. The long press is what lets this coexist with the
    /// enclosing `ScrollView`: a finger that moves right away scrolls, one
    /// that stays put long enough starts a reorder instead — the same
    /// bargain the Home Screen makes.
    private func reorderGesture(for accountID: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(coordinateSpace: .named(Self.reorderSpace)))
            .onChanged { value in
                switch value {
                case .first(true):
                    if draggingID != accountID {
                        draggingID = accountID
                        dragTranslation = 0
                    }
                case .second(true, let drag):
                    guard draggingID == accountID, let drag else { return }
                    dragTranslation = drag.translation.height
                    setDropTarget(hitTest(drag.location, excluding: accountID))
                default:
                    break
                }
            }
            .onEnded { _ in endReorder(of: accountID) }
    }

    /// The section under the finger, if it isn't the one being dragged.
    /// The dragged card's own slot still counts as occupied, which is what
    /// makes releasing back where you started a no-op rather than an
    /// accident.
    private func hitTest(_ location: CGPoint, excluding accountID: String) -> String? {
        sectionFrames.first { $0.key != accountID && $0.value.contains(location) }?.key
    }

    private func endReorder(of accountID: String) {
        let target = dropTargetID
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            if draggingID == accountID, let target {
                model.moveAccount(accountID, onto: target)
            }
            // Reset inside the same transaction as the move, so the card
            // travels from where it was released into its new slot instead
            // of snapping back first and then jumping.
            draggingID = nil
            dragTranslation = 0
            dropTargetID = nil
        }
    }

    /// Same Reduce Motion rule the app's other transitions follow: the
    /// state still changes, it just doesn't animate.
    private func setDropTarget(_ id: String?) {
        guard dropTargetID != id else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.15)) { dropTargetID = id }
    }

    /// Names the coordinate space section frames and drag locations are
    /// both resolved in, so comparing the two means something.
    private static let reorderSpace = "dashboard.accounts"

    private var addAccountButton: some View {
        Button {
            showingConnect = true
        } label: {
            Label("Add account", systemImage: "plus.circle")
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }
}

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
