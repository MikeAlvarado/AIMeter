import SwiftUI
import WidgetKit
import UsageKit

struct ContentView: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.scenePhase) private var scenePhase
    /// The Dashboard's navigation, held here so the Mac's popover can open
    /// an account's detail in it (`AppChrome.openAccount`).
    @State private var path = NavigationPath()
    #if os(iOS)
    /// Compact height == iPhone in landscape → fullscreen usage mode.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// The full tour at the first launch (see `Tour`), and again from
    /// Settings (`.tourShowRequest`).
    @State private var showsTour = Tour.dueAtLaunch()
    /// The tour's last step asked to connect: the Dashboard's Connect sheet
    /// opens once the tour is gone (`.tourConnectRequest`).
    @State private var connectsAfterTour = false
    /// This version's notes, once after the App Store installs it (the
    /// Mac shows them in its update window instead); never over a first
    /// launch's tour, which shows what is new as well.
    @State private var whatsNew = Tour.dueAtLaunch() ? nil : WhatsNew.dueAtLaunch()
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            if verticalSizeClass == .compact {
                LandscapeUsageView()
            } else {
                dashboard
            }
            #else
            dashboard
            #endif
        }
        #if os(iOS)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundRefresh.scheduleNext()
            }
            if phase == .active {
                // Always re-render widgets from the foreground, even when
                // the fetch below fails or is throttled — otherwise a
                // freshly updated app can leave placed widgets showing
                // WidgetKit's archived render of the previous version.
                WidgetReload.all()
                Task {
                    // The user may have flipped the permission in Settings.
                    await model.refreshNotificationAuthorization()
                    // Coming back to the foreground: fetch fresh usage
                    // (throttled) so app and widgets update right away.
                    await model.refreshAllIfStale()
                }
            }
        }
        .sheet(item: $whatsNew, onDismiss: { WhatsNew.lastSeen = AppVersion.current }) { release in
            WhatsNewSheet(release: release) { whatsNew = nil }
                .withAppModels(model, prefs)
                // Its features' cards show with the notes: offered.
                .onAppear { Tour.markOffered(release.items.compactMap(\.tourFeature)) }
        }
        .fullScreenCover(isPresented: $showsTour, onDismiss: {
            guard connectsAfterTour else { return }
            connectsAfterTour = false
            NotificationCenter.default.post(name: .tourConnectRequest, object: nil)
        }) {
            TourCover { connect in
                Tour.finish()
                connectsAfterTour = connect
                showsTour = false
            }
            .withAppModels(model, prefs)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .tourShowRequest) {
                showsTour = true
            }
        }
        .task {
            await model.refreshAll()
        }
        #else
        // The launch refresh is the AppDelegate's: this window may never
        // open (a restored Settings window) or close at once (a hidden
        // Dock icon), and a view's `.task` is cancelled with it. Here only
        // what went stale while it was closed, in a task its closing
        // doesn't cancel.
        .onAppear {
            Task { await model.refreshAllIfStale() }
        }
        #endif
    }

    private var dashboard: some View {
        NavigationStack(path: $path) {
            // The Dashboard draws its own header on iOS, and hides the
            // navigation bar itself but on iPhone Duo's side bar
            // (`DashboardSideBar`); the Mac's window toolbar carries its
            // buttons instead.
            DashboardView()
        }
        // An account disconnected (from its own settings page, Settings,
        // or the Mac's Settings window): back to the Dashboard, since the
        // detail and the settings page in the stack have nothing left to
        // show. Before 4.0.1 the settings page popped onto an empty
        // Provider Detail titled with a provider's name, which read as
        // another account, and the stack could stick (Mike, 2026-10-21).
        .onChange(of: model.accounts.map(\.account.accountID)) { old, new in
            if !Set(old).isSubset(of: Set(new)), !path.isEmpty {
                path = NavigationPath()
            }
        }
        #if os(iOS) && DEBUG
        // `-AIMeterOpenAccount <accountID>` opens that account's detail at
        // launch, and with `-AIMeterOpenAccountSettings YES` its settings
        // page, to check or capture them without a tap.
        .onAppear {
            guard path.isEmpty, let id = UserDefaults.standard.string(forKey: "AIMeterOpenAccount") else { return }
            path.append(id)
            if UserDefaults.standard.bool(forKey: "AIMeterOpenAccountSettings") {
                path.append(AccountSettingsRoute(accountID: id))
            }
        }
        #endif
        #if os(macOS)
        // A click on an account in the menu bar popover opens its detail
        // here (`AppChrome.openAccount`).
        .onAppear {
            AppChrome.presentAccount = { accountID in
                path = NavigationPath()
                path.append(accountID)
            }
            AppChrome.deliverPendingAccount()
        }
        .onDisappear {
            AppChrome.presentAccount = nil
        }
        // The detail screens' toggles as trailing switches, like Settings'.
        .toggleStyle(.settingsSwitch)
        // Room for two accounts and an incident notice without scrolling;
        // a window restored smaller than this grows to it.
        .frame(minWidth: 380, minHeight: 560)
        #endif
    }
}

#Preview {
    ContentView()
        .environment(UsageModel())
        .environment(PreferencesModel())
}
