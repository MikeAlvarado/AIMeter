import SwiftUI
import WidgetKit
import UsageKit

struct ContentView: View {
    @Environment(UsageModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
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
                WidgetCenter.shared.reloadAllTimelines()
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
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .tourShowRequest) {
                showsTour = true
            }
        }
        #endif
        .task {
            await model.refreshAll()
        }
    }

    private var dashboard: some View {
        NavigationStack {
            DashboardView()
                #if os(iOS)
                // The Dashboard draws its own header on iOS; the Mac's
                // window toolbar carries its buttons instead.
                .toolbar(.hidden, for: .automatic)
                #endif
        }
        #if os(macOS)
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
