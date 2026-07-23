import Foundation
import Observation
import UserNotifications
import UsageKit

/// Per-provider UI state: the last known snapshot (kept visible even when a
/// refresh fails, with the error surfaced alongside), the last error, and
/// whether this provider needs the user to connect.
struct ProviderState {
    var snapshot: UsageSnapshot?
    var lastError: String?
    var needsConnection: Bool
}

/// UI-facing state, keyed by provider ID so one provider's failure never
/// blanks another's. `AppConfig.providerIDs` lists every provider this
/// build knows about; today that's just Claude.
@Observable
final class UsageModel {
    private var providerStates: [String: ProviderState] = [:]
    private(set) var isRefreshing = false

    private let service = RefreshService()
    private let preferences = NotificationPreferences()
    #if os(macOS)
    @ObservationIgnored private var refreshTimer: Timer?
    #endif

    init() {
        for providerID in AppConfig.providerIDs {
            providerStates[providerID] = ProviderState(
                snapshot: service.lastSnapshot(for: providerID),
                lastError: nil,
                needsConnection: Self.initialNeedsConnection(for: providerID)
            )
        }
        #if os(macOS)
        AppEnvironment.shared = self
        rebuildTimer(interval: Preferences.load().refreshCadence.interval)
        #endif
    }

    private static func initialNeedsConnection(for providerID: String) -> Bool {
        #if os(macOS)
        // Assume connected; the first refresh flips this if no credentials
        // are found (neither Claude Code's nor the app's own).
        return false
        #else
        return !RefreshService.storedCredentialsExist()
        #endif
    }

    func snapshot(for providerID: String) -> UsageSnapshot? { providerStates[providerID]?.snapshot }
    func lastError(for providerID: String) -> String? { providerStates[providerID]?.lastError }
    func needsConnection(for providerID: String) -> Bool { providerStates[providerID]?.needsConnection ?? true }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for result in await service.refresh() {
            apply(result)
        }
    }

    /// Applies one provider's refresh outcome to its own state slot —
    /// success updates the snapshot, "no credentials" flips the connect
    /// prompt, any other error is surfaced alongside the last-known
    /// snapshot, and a cancelled/superseded fetch (no snapshot, no error)
    /// leaves the existing state untouched.
    private func apply(_ result: ProviderRefreshResult) {
        var state = providerStates[result.providerID]
            ?? ProviderState(snapshot: nil, lastError: nil, needsConnection: true)
        if let snapshot = result.snapshot {
            state.snapshot = snapshot
            state.lastError = nil
            state.needsConnection = false
        } else if let usageError = result.error as? UsageError, case .credentialsNotFound = usageError {
            state.needsConnection = true
            state.lastError = nil
        } else if let usageError = result.error as? UsageError {
            state.lastError = usageError.errorDescription
        } else if let error = result.error {
            state.lastError = error.localizedDescription
        }
        providerStates[result.providerID] = state
    }

    /// Foreground-activation refresh: skips the network when every
    /// provider's snapshot is still fresh, so quick app switches don't
    /// refetch, but returning after a while updates the dashboard — and,
    /// via the refresh flow, pushes new snapshots to the widgets immediately.
    func refreshIfStale(maxAge: TimeInterval = 60) async {
        let allFresh = providerStates.values.allSatisfy { state in
            guard let fetchedAt = state.snapshot?.fetchedAt else { return false }
            return Date().timeIntervalSince(fetchedAt) < maxAge
        }
        if allFresh { return }
        await refresh()
    }

    /// True once pace has warmed up (a couple of sessions observed since the
    /// account connected). Until then, views withhold the pace caption and
    /// the forecast, showing a "learning" state instead of asserting a pace
    /// from too little history.
    func paceReady(for providerID: String) -> Bool {
        _ = providerStates[providerID] // re-read when a refresh lands
        return PaceCalculator.isReady(observingSince: service.paceObservingSince(for: providerID))
    }

    /// Called by the connect sheet after a successful OAuth exchange.
    func completeConnection(_ credentials: ClaudeCredentials) async {
        do {
            try await service.storeConnection(credentials)
            providerStates["claude"]?.needsConnection = false
            providerStates["claude"]?.lastError = nil
            await refresh()
        } catch {
            providerStates["claude"]?.lastError =
                (error as? UsageError)?.errorDescription ?? error.localizedDescription
        }
    }

    func disconnect() {
        do {
            try service.disconnect()
            providerStates["claude"] = ProviderState(snapshot: nil, lastError: nil, needsConnection: true)
        } catch {
            providerStates["claude"]?.lastError = error.localizedDescription
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

    func notificationsEnabled(for providerID: String, kind: UsageWindow.Kind) -> Bool {
        _ = notificationsRevision
        return preferences.isEnabled(for: providerID, kind: kind)
    }

    func setNotificationsEnabled(_ enabled: Bool, for providerID: String, kind: UsageWindow.Kind) {
        let snapshot = self.snapshot(for: providerID)
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
            preferences.setEnabled(enabled, for: providerID, kind: kind)
            notificationsRevision += 1
            await NotificationScheduler.rescheduleResets(for: snapshot, providerID: providerID, preferences: preferences)
        }
    }

    // MARK: Smart notifications (global run-out / early-reset, across all providers)

    var runOutWarningsEnabled: Bool {
        _ = notificationsRevision
        return preferences.runOutWarningsEnabled
    }

    var earlyResetAlertsEnabled: Bool {
        _ = notificationsRevision
        return preferences.earlyResetAlertsEnabled
    }

    func setRunOutWarningsEnabled(_ enabled: Bool) {
        let statesByProvider = providerStates
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            preferences.runOutWarningsEnabled = enabled
            notificationsRevision += 1
            // Immediate scheduling uses the average rate (no history needed);
            // the next fetch refines it with the recent rate. Every
            // connected provider gets its own rescheduled set.
            for (providerID, state) in statesByProvider {
                let projections = state.snapshot.map {
                    RunOutPredictor.averageProjections(for: $0, minimumUsedPct: RunOutPredictor.alertMinimumUsedPct)
                } ?? [:]
                await NotificationScheduler.rescheduleRunOuts(projections, providerID: providerID, preferences: preferences)
            }
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
