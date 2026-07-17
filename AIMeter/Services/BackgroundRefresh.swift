#if os(iOS)
import BackgroundTasks
import Foundation

/// Schedules the next BGAppRefreshTask at the user-selected cadence. The
/// handler itself is registered declaratively via
/// `.backgroundTask(.appRefresh(...))` in AIMeterApp. iOS treats the
/// interval as an earliest date, not a guarantee.
enum BackgroundRefresh {
    static func scheduleNext() {
        let cadence = Preferences.load().refreshCadence
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: cadence.interval)
        do {
            try BGTaskScheduler.shared.submit(request)
            Preferences.recordScheduled()
        } catch {
            // Duplicate submissions and simulator restrictions are expected.
        }
    }
}
#endif
