import SwiftUI
import WatchKit

/// The Watch app: what the iPhone last fetched, for every account, and a
/// Refresh that asks the iPhone. No credentials, no fetching of its own;
/// see "Apple Watch" in the repo-root CLAUDE.md.
@main
struct AIMeterWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @State private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(store)
                .tint(Theme.accent)
        }
    }
}

/// Background refresh: every half hour, if what the Watch holds is older
/// than that, it asks the iPhone (which `sendMessage` wakes in the
/// background when it isn't running).
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchStore.scheduleBackgroundRefresh()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if task is WKApplicationRefreshBackgroundTask {
                WatchStore.shared.requestRefreshIfStale()
                WatchStore.scheduleBackgroundRefresh()
            }
            task.setTaskCompletedWithSnapshot(false)
        }
    }
}
