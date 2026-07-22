import Foundation
import Observation
import UserNotifications
import UsageKit

/// UI-facing state. Wraps RefreshService and keeps the last known snapshot
/// visible even when a refresh fails (the error is surfaced alongside).
@Observable
final class UsageModel {
    private(set) var snapshot: UsageSnapshot?
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    /// True when there are no usable credentials — dashboard shows the
    /// connect card instead of usage rows.
    private(set) var needsConnection: Bool

    private let service = RefreshService()
    private let preferences = NotificationPreferences()
    #if os(macOS)
    @ObservationIgnored private var refreshTimer: Timer?
    #endif

    init() {
        snapshot = service.lastSnapshot()
        #if os(macOS)
        // Assume connected; the first refresh flips this if no credentials
        // are found (neither Claude Code's nor the app's own).
        needsConnection = false
        AppEnvironment.shared = self
        #else
        needsConnection = !RefreshService.storedCredentialsExist()
        #endif
        #if os(macOS)
        rebuildTimer(interval: Preferences.load().refreshCadence.interval)
        #endif
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            snapshot = try await service.refresh()
            lastError = nil
            needsConnection = false
        } catch let error as UsageError {
            if case .credentialsNotFound = error {
                needsConnection = true
                lastError = nil
            } else {
                lastError = error.errorDescription
            }
        } catch is CancellationError {
            // A superseded refresh (pull-to-refresh released, scene change)
            // is not an error worth showing.
        } catch let error as URLError where error.code == .cancelled {
            // Same: the URL task was cancelled by a newer refresh.
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Foreground-activation refresh: skips the network when the snapshot
    /// is still fresh, so quick app switches don't refetch, but returning
    /// after a while updates the dashboard — and, via the refresh flow,
    /// pushes the new snapshot to the widgets immediately.
    func refreshIfStale(maxAge: TimeInterval = 60) async {
        if let fetchedAt = snapshot?.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < maxAge {
            return
        }
        await refresh()
    }

    /// Called by the connect sheet after a successful OAuth exchange.
    func completeConnection(_ credentials: ClaudeCredentials) async {
        do {
            try await service.storeConnection(credentials)
            needsConnection = false
            lastError = nil
            await refresh()
        } catch {
            lastError = (error as? UsageError)?.errorDescription ?? error.localizedDescription
        }
    }

    func disconnect() {
        do {
            try service.disconnect()
            snapshot = nil
            lastError = nil
            needsConnection = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Notification preferences

    /// True when the user denied notification permission in the system
    /// settings — the toggles card shows a warning with a shortcut there
    /// instead of silently doing nothing.
    private(set) var notificationsBlocked = false
    /// Bumped whenever a toggle's stored value changes, so bindings that
    /// read UserDefaults through `notificationsEnabled` re-evaluate.
    private var notificationsRevision = 0

    func refreshNotificationAuthorization() async {
        let status = await NotificationScheduler.authorizationStatus()
        await MainActor.run { notificationsBlocked = status == .denied }
    }

    func notificationsEnabled(for kind: UsageWindow.Kind) -> Bool {
        _ = notificationsRevision
        return preferences.isEnabled(for: kind)
    }

    func setNotificationsEnabled(_ enabled: Bool, for kind: UsageWindow.Kind) {
        let snapshot = self.snapshot
        Task { @MainActor in
            if enabled {
                guard await NotificationScheduler.ensureAuthorization() else {
                    // Denied: don't persist the toggle — snap it back off
                    // and surface the blocked state.
                    notificationsBlocked = true
                    notificationsRevision += 1
                    return
                }
                notificationsBlocked = false
            }
            preferences.setEnabled(enabled, for: kind)
            notificationsRevision += 1
            await NotificationScheduler.rescheduleResets(for: snapshot, preferences: preferences)
        }
    }

    // MARK: Smart notifications (global run-out / early-reset)

    var runOutWarningsEnabled: Bool {
        _ = notificationsRevision
        return preferences.runOutWarningsEnabled
    }

    var earlyResetAlertsEnabled: Bool {
        _ = notificationsRevision
        return preferences.earlyResetAlertsEnabled
    }

    func setRunOutWarningsEnabled(_ enabled: Bool) {
        let snapshot = self.snapshot
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            preferences.runOutWarningsEnabled = enabled
            notificationsRevision += 1
            // Immediate scheduling uses the average rate (no history needed);
            // the next fetch refines it with the recent rate.
            let projections = snapshot.map {
                RunOutPredictor.averageProjections(for: $0, minimumUsedPct: RunOutPredictor.alertMinimumUsedPct)
            } ?? [:]
            await NotificationScheduler.rescheduleRunOuts(projections, preferences: preferences)
        }
    }

    func setEarlyResetAlertsEnabled(_ enabled: Bool) {
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            preferences.earlyResetAlertsEnabled = enabled
            notificationsRevision += 1
            // Nothing to schedule now — these fire on detection at fetch time.
        }
    }

    var nearLimitEnabled: Bool {
        _ = notificationsRevision
        return preferences.nearLimitEnabled
    }

    var nearLimitThreshold: Double {
        _ = notificationsRevision
        return preferences.nearLimitThreshold
    }

    var limitReachedEnabled: Bool {
        _ = notificationsRevision
        return preferences.limitReachedEnabled
    }

    func setNearLimitEnabled(_ enabled: Bool) {
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            preferences.nearLimitEnabled = enabled
            notificationsRevision += 1
            // Detection-based: fires on the next crossing at fetch time.
        }
    }

    func setNearLimitThreshold(_ threshold: Double) {
        preferences.nearLimitThreshold = threshold
        notificationsRevision += 1
    }

    func setLimitReachedEnabled(_ enabled: Bool) {
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            preferences.limitReachedEnabled = enabled
            notificationsRevision += 1
        }
    }

    /// Shared permission gate for enabling a notification toggle: a denied
    /// system permission snaps the toggle back off and surfaces the blocked
    /// state. Returns whether the caller should proceed to persist.
    private func authorizeIfEnabling(_ enabled: Bool) async -> Bool {
        if enabled {
            guard await NotificationScheduler.ensureAuthorization() else {
                notificationsBlocked = true
                notificationsRevision += 1
                return false
            }
            notificationsBlocked = false
        }
        return true
    }

    // MARK: - macOS refresh timer

    #if os(macOS)
    func rebuildTimer(interval: TimeInterval) {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                await AppEnvironment.shared?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        Preferences.recordScheduled()
    }
    #endif
}

#if os(macOS)
/// Lets the repeating Timer reach the live model without retaining cycles
/// in the closure signature Timer requires.
enum AppEnvironment {
    static weak var shared: UsageModel?
}
#endif
