import Foundation
import UsageKit
#if os(macOS)
import AppKit
#endif

/// The macOS-only plumbing that keeps the model refreshing with no window
/// open: the `NSBackgroundActivityScheduler` cadence and the wake /
/// activation observers. See the type doc in `UsageModel.swift`.
extension UsageModel {
    // MARK: - macOS refresh schedule

    #if os(macOS)
    /// Rebuilds the repeating refresh at the user's cadence.
    ///
    /// `NSBackgroundActivityScheduler` rather than a run-loop `Timer`: a
    /// menu-bar-only app with no visible window is a prime App Nap
    /// candidate — which is exactly what AIMeter becomes once the Dock icon
    /// is hidden — and Nap throttles timers unpredictably. The scheduler is
    /// Nap- and power-aware, and trades an exact fire instant (nothing here
    /// needs one) for actually running.
    func rebuildRefreshSchedule(interval: TimeInterval) {
        refreshScheduler?.invalidate()
        let scheduler = NSBackgroundActivityScheduler(identifier: AppConfig.refreshActivityID)
        scheduler.repeats = true
        scheduler.interval = interval
        // The cadence is a "roughly every N" contract, not a deadline, so a
        // wide tolerance lets the system coalesce this with other wake-ups
        // instead of waking the CPU on AIMeter's account alone.
        scheduler.tolerance = interval * 0.2
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            // Called off the main actor; hop back before touching the model,
            // and report completion so the scheduler re-arms.
            Task { @MainActor in
                await AppEnvironment.shared?.refreshAll()
                completion(.finished)
            }
        }
        refreshScheduler = scheduler
        Preferences.recordScheduled()
    }

    /// Neither a scheduler nor a timer fires while the Mac is asleep. Waking
    /// does re-arm the schedule, but not necessarily right away, so nudge it
    /// — `refreshAllIfStale` decides whether anything is actually due,
    /// making this a no-op when every snapshot is still fresh.
    ///
    /// Registered once, from `init`: the model is owned by the App scene for
    /// the whole process lifetime, and the closure holds nothing strongly
    /// (it reaches the model through the same weak `AppEnvironment` the
    /// schedule uses), so there is no observer to unregister before exit.
    func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let cadence = Preferences.load().refreshCadence.interval
                await AppEnvironment.shared?.refreshAllIfStale(maxAge: cadence)
            }
        }
    }

    /// The iOS side already re-checks notification authorization whenever
    /// `scenePhase` returns to `.active` ("the user may have flipped the
    /// permission in Settings" — `ContentView`), because System Settings and
    /// the app trade the foreground there. macOS has no scene phase, but the
    /// same trip — alt-tab to System Settings, flip the toggle, alt-tab back
    /// — is if anything more common on a desktop, and `notificationsBlocked`
    /// (the in-app warning banner, and the stale value a toggle's `.denied`
    /// check can otherwise race right after such a change) was only ever
    /// getting refreshed when a Provider Detail view happened to re-appear.
    /// `didBecomeActiveNotification` is the direct macOS equivalent of that
    /// iOS signal. Same no-unregister reasoning as `observeWake()`.
    func observeActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await AppEnvironment.shared?.refreshNotificationAuthorization()
            }
        }
    }
    #endif
}

#if os(macOS)
/// Lets the background refresh schedule and the wake observer reach the
/// live model from closures that can't capture it strongly.
enum AppEnvironment {
    static weak var shared: UsageModel?
}
#endif
