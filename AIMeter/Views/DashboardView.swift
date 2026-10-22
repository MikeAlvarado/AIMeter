import SwiftUI
import UsageKit

struct DashboardView: View {
    @Environment(UsageModel.self) var model
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var showingSettings = false
    @State private var showingConnect = false
    /// Reconnect requested from a surface that can't present the sheet
    /// itself (the menu bar popover) — see `AppChrome.connect(_:)`.
    @State private var reconnecting: ConnectedAccount?
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
                #if os(iOS)
                header
                #endif
                // Only while the provider itself reports a problem — on a
                // normal day the dashboard looks exactly as it always has.
                if let incident = model.activeIncident {
                    ServiceStatusBanner(
                        providerName: ProviderCatalog.displayName(for: incident.providerID),
                        status: incident.status,
                        fallbackURL: ProviderCatalog.statusPageURL(for: incident.providerID)
                    )
                }
                #if os(macOS)
                // Only while an update waits for a restart.
                UpdateReadyNotice()
                #endif
                providerSection
                #if os(macOS)
                // Per machine, not per account — see `ClaudeCodeUsageModel`.
                VStack(alignment: .leading, spacing: 10) {
                    ClaudeCodeSection()
                }
                #endif
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
        .appBackground()
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
        .navigationDestination(for: AccountSettingsRoute.self) { route in
            AccountSettingsPage(accountID: route.accountID, dismissesOnDisconnect: false)
        }
        #if os(macOS)
        .navigationDestination(for: ClaudeCodeUsageRoute.self) { _ in
            ClaudeCodeUsageView()
        }
        #endif
        #if os(iOS)
        .refreshable {
            refreshRequests += 1
            await model.refreshAll()
        }
        // "Show the tour" closes Settings first; the tour opens once the
        // sheet is gone.
        .sheet(isPresented: $showingSettings, onDismiss: Tour.deliverPendingShow) {
            SettingsSheet()
        }
        // The tour's last step: connect, once the tour has closed.
        .task {
            for await _ in NotificationCenter.default.notifications(named: .tourConnectRequest) {
                showingConnect = true
            }
        }
        #endif
        .sheet(isPresented: $showingConnect) {
            ConnectAccountSheet()
        }
        .sheet(item: $reconnecting) { account in
            ConnectAccountSheet(reconnecting: account)
        }
        #if os(macOS)
        // When the accounts last refreshed, once, under the window's title
        // (a card says so itself only once its figures go stale).
        .navigationSubtitle(lastUpdatedLabel ?? "")
        // The Mac's window already has a title bar that says "AIMeter",
        // so the in-page title and the floating round buttons became the
        // window's toolbar: the title once, Refresh and Settings at its
        // trailing edge, where a Mac app keeps them.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("Refresh"))
                } else {
                    Button {
                        refreshRequests += 1
                        Task { await model.refreshAll() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help(String(localized: "Refresh"))
                    // ⌘R is the Usage menu's (`AIMeterApp.commands`), not
                    // this button's: declaring it here too fired both.
                }
                Button {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help(String(localized: "Settings"))
            }
        }
        .onAppear(perform: registerConnectHook)
        .onDisappear {
            AppChrome.presentConnect = nil
        }
        #endif
    }

    #if os(macOS)
    /// The menu bar popover and the island present no sheets of their
    /// own; they hand a connect request to this window (`AppChrome.connect`).
    private func registerConnectHook() {
        AppChrome.presentConnect = { request in
            switch request {
            case .add: showingConnect = true
            case .reconnect(let account): reconnecting = account
            }
        }
        AppChrome.deliverPendingConnect()
    }
    #endif

    /// "Updated 2 min ago" for the most recent refresh of any account: the
    /// one freshness line on the Dashboard. A card whose own figures fall
    /// behind says so itself (`UsageStatusFooter`, `.whenStale`).
    var lastUpdatedLabel: String? {
        model.accounts.compactMap(\.snapshot?.fetchedAt).max().map { UsageFormatting.updatedLabel($0) }
    }

    #if os(iOS)
    private var header: some View {
        ZStack {
            // No app title (Mike, 2026-10-21: the cards are the screen);
            // only when the accounts last refreshed, between the buttons.
            if let lastUpdatedLabel {
                Text(lastUpdatedLabel)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .contentTransition(.opacity)
            }
            HStack {
                headerButtons
            }
        }
    }

    private var headerButtons: some View {
        HStack {
            RoundIconButton(systemName: "gearshape") {
                showingSettings = true
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
    #endif

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            Label("Add account", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .contentShape(Capsule())
                .glassControl(in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}
