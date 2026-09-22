import SwiftUI
import UsageKit

struct DashboardView: View {
    @Environment(UsageModel.self) var model
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var showingSettings = false
    @State private var showingConnect = false
    /// Bumped per user-initiated refresh; drives the haptic only.
    @State private var refreshRequests = 0
    /// The section being dragged, how far it has moved, and which section
    /// it would drop onto — see `accountSection(_:)` in
    /// `DashboardView+Reorder.swift` for why the reorder carries this state
    /// itself instead of using SwiftUI's drag and drop. Internal rather
    /// than private only so that extension file can reach it.
    @State var draggingID: String?
    @State var dragTranslation: CGFloat = 0
    /// Where the finger was when the card lifted (UIKit path only — the
    /// SwiftUI drag reports a translation of its own).
    @State var dragStartY: CGFloat = 0
    @State var dropTargetID: String?
    /// Each section's on-screen rect, so a drag can tell what it's over.
    @State var sectionFrames: [String: CGRect] = [:]
    /// When the scroll content last moved — see the type's own note for
    /// why this exists and why it is a reference, not plain `@State`.
    @State var scrollTracker = ScrollMovementTracker()
    @Environment(\.accessibilityReduceMotion) var reduceMotion

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
