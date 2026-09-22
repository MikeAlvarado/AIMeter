import SwiftUI
import UsageKit

struct DashboardView: View {
    @Environment(UsageModel.self) private var model
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var showingSettings = false
    @State private var showingConnect = false
    /// Bumped per user-initiated refresh; drives the haptic only.
    @State private var refreshRequests = 0
    /// The section being dragged, how far it has moved, and which section
    /// it would drop onto — see `accountSection(_:)` for why the reorder
    /// carries this state itself instead of using SwiftUI's drag and drop.
    @State private var draggingID: String?
    @State private var dragTranslation: CGFloat = 0
    /// Where the finger was when the card lifted (UIKit path only — the
    /// SwiftUI drag reports a translation of its own).
    @State private var dragStartY: CGFloat = 0
    @State private var dropTargetID: String?
    /// Each section's on-screen rect, so a drag can tell what it's over.
    @State private var sectionFrames: [String: CGRect] = [:]
    /// When the scroll content last moved — see the type's own note for
    /// why this exists and why it is a reference, not plain `@State`.
    @State private var scrollTracker = ScrollMovementTracker()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header
                providerSection
            }
            .padding(20)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DashboardScrollOffsetKey.self,
                        value: proxy.frame(in: .named(Self.scrollSpace)).minY
                    )
                }
            }
        }
        .coordinateSpace(name: Self.scrollSpace)
        .onPreferenceChange(DashboardScrollOffsetKey.self) { _ in
            scrollTracker.lastMovement = Date()
        }
        // While a card is lifted, the list must not scroll under it. On
        // iOS 18+ UIKit already guarantees that (a recognised press prevents
        // the pan for that touch — see `ReorderPressRecognizer`); this makes
        // the same promise explicitly for the iOS 17/macOS SwiftUI path and
        // costs nothing on the other. The finger has been still for the whole
        // press when this flips, so there is never a pan in progress to cut.
        .scrollDisabled(draggingID != nil)
        .background(Theme.background)
        // Soft tap when the *user* starts a refresh — pull gesture or
        // button alike. Keyed on the request count, not `isRefreshing`:
        // that also flips for the foreground auto-refresh, which would
        // buzz the phone for something the user didn't do.
        .sensoryFeedback(.impact(flexibility: .soft), trigger: refreshRequests)
        // And a firmer one the moment a card lifts, which is the only
        // confirmation that the hold registered — the card hasn't moved yet.
        .sensoryFeedback(.impact(weight: .medium), trigger: draggingID) { was, now in
            was == nil && now != nil
        }
        .navigationDestination(for: String.self) { accountID in
            ProviderDetailView(accountID: accountID)
        }
        #if os(iOS)
        .refreshable {
            refreshRequests += 1
            await model.refreshAll()
        }
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
                refreshRequests += 1
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
                        #if os(macOS)
                        // The way back to the zero-setup path after the
                        // user disconnected the CLI-mirrored account (see
                        // `Preferences.autoDetectDeclined`).
                        if model.canRedetectClaudeCodeLogin {
                            Button {
                                Task { await model.redetectClaudeCodeLogin() }
                            } label: {
                                Text("Use Claude Code's login instead")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.accent)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        #endif
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(model.accounts) { usage in
                    accountSection(usage)
                }
                // Not in demo mode: `completeConnection` would register a
                // real account underneath the fabricated row, invisible
                // until Exit Demo.
                if !model.isDemoMode {
                    addAccountButton
                }
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
            moveDown: canReorder && index < model.accounts.count - 1 ? { model.moveAccount(usage.id, by: 1) } : nil,
            canRename: !model.isDemoMode
        )

        if canReorder {
            withReorderGesture(
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
                    .zIndex(isDragging ? 1 : 0),
                for: usage.id
            )
        } else {
            section
        }
    }

    /// Two implementations of one interaction. iOS 18+ gets a UIKit
    /// `UILongPressGestureRecognizer` (`ReorderPressRecognizer`), because on
    /// those systems any SwiftUI gesture with a drag in it stops the
    /// enclosing ScrollView from panning for touches that begin on the card
    /// — the whole story is on that type. iOS 17 and macOS keep the SwiftUI
    /// gesture, which has no such problem there. Both report through
    /// `handleReorderPhase`/`lift`/`drag`/`endReorder`, so the reorder itself
    /// behaves identically.
    @ViewBuilder
    private func withReorderGesture(_ content: some View, for accountID: String) -> some View {
        #if os(iOS)
        if #available(iOS 18, *) {
            content.gesture(
                ReorderPressRecognizer(coordinateSpace: .named(Self.reorderSpace)) { phase in
                    handleReorderPhase(phase, for: accountID)
                }
            )
        } else {
            content.gesture(reorderGesture(for: accountID))
        }
        #else
        content.gesture(reorderGesture(for: accountID))
        #endif
    }

    private func handleReorderPhase(_ phase: ReorderPhase, for accountID: String) {
        switch phase {
        case .began(let location):
            lift(accountID)
            if draggingID == accountID {
                dragStartY = location.y
            }
        case .moved(let location):
            drag(accountID, translation: location.y - dragStartY, location: location)
        case .ended, .cancelled:
            endReorder(of: accountID)
        }
    }

    /// The hold completed: lift the card — unless the content moved during
    /// the press, in which case this was a scroll (see `scrollTracker`).
    private func lift(_ accountID: String) {
        guard !scrollTracker.movedRecently, draggingID != accountID else { return }
        draggingID = accountID
        dragTranslation = 0
    }

    private func drag(_ accountID: String, translation: CGFloat, location: CGPoint) {
        guard draggingID == accountID else { return }
        dragTranslation = translation
        setDropTarget(hitTest(location, excluding: accountID))
    }

    /// Hold, then drag. The long press is what lets this coexist with the
    /// enclosing `ScrollView`: a finger that moves right away scrolls, one
    /// that stays put long enough starts a reorder instead — the same
    /// bargain the Home Screen makes.
    ///
    /// The hold is the system's own long-press duration (0.5 s), not
    /// shorter. It shipped at 0.3 s and that was a bug: a thumb that settles
    /// on a card for a third of a second before it starts to scroll — the
    /// normal way to begin a scroll, not a deliberate hold — completed the
    /// press, lifted the card, and the scroll it meant to do became a
    /// reorder (reproduced on the simulator with a 400 ms dwell: the card
    /// changed places instead of the list scrolling). Anything that moves
    /// more than 10 pt inside the window still fails the press and scrolls,
    /// so the only thing 0.5 s costs is the deliberate hold taking as long
    /// as every other long press on the platform.
    ///
    /// The duration alone is not enough, though, because `LongPressGesture`
    /// measures its `maximumDistance` in the pressed view's *own*
    /// coordinate space — and a card scrolls with the finger. To the press,
    /// a finger that is scrolling the list never moves at all, so the press
    /// completed mid-scroll, lifted the card (drag shadow and haptic
    /// included) while the list was still moving, and the finger's release
    /// ended a "reorder" nobody started — the behaviour reported from a
    /// device. The `ScrollView`'s own content offset is the one thing that
    /// does see a scroll, so `scrollTracker` records when it last changed and
    /// a press that completes while the content moved anywhere inside the
    /// press window is treated as the scroll it is: it never lifts, and the
    /// drag values that follow are ignored (`draggingID` stays nil).
    ///
    /// iOS 17 and macOS only — iOS 18+ uses `ReorderPressRecognizer`
    /// instead (see `withReorderGesture(_:for:)` for why).
    private func reorderGesture(for accountID: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(coordinateSpace: .named(Self.reorderSpace)))
            .onChanged { value in
                switch value {
                case .first(true):
                    lift(accountID)
                case .second(true, let drag):
                    guard let drag else { return }
                    self.drag(accountID, translation: drag.translation.height, location: drag.location)
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
    /// The `ScrollView`'s own space, which the content's offset is measured
    /// in — unlike `reorderSpace`, which scrolls along with the content and
    /// therefore never sees a scroll happen.
    private static let scrollSpace = "dashboard.scroll"

    /// Remembers when the Dashboard's scroll content last moved, so the
    /// reorder gesture can refuse to lift a card mid-scroll (see
    /// `reorderGesture(for:)`).
    ///
    /// A reference held in `@State` rather than a `Date` in `@State` on
    /// purpose: the offset changes on every frame of a scroll, and nothing on
    /// screen depends on it — storing it as view state would invalidate the
    /// whole Dashboard body once per scrolled frame for no visible result,
    /// which is exactly the kind of thing that makes a scroll stutter.
    /// Mutating a plain class property invalidates nothing.
    private final class ScrollMovementTracker {
        var lastMovement: Date = .distantPast

        /// True if the content moved at any point inside the current press
        /// window. The window is the press duration plus a little slack, so
        /// a finger that touched down to stop a decelerating list — content
        /// still moving at the instant of contact — also reads as a scroll
        /// rather than as the start of a hold.
        var movedRecently: Bool {
            Date().timeIntervalSince(lastMovement) < 0.6
        }
    }

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
