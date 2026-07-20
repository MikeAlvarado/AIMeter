import SwiftUI
import WidgetKit
import UsageKit

struct ContentView: View {
    @Environment(UsageModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    /// Compact height == iPhone in landscape → fullscreen usage mode.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
                    await model.refreshIfStale()
                }
            }
        }
        #endif
        .task {
            await model.refresh()
        }
    }

    private var dashboard: some View {
        NavigationStack {
            DashboardView()
                .toolbar(.hidden, for: .automatic)
        }
    }
}

#Preview {
    ContentView()
        .environment(UsageModel())
        .environment(PreferencesModel())
}
