import Foundation
import UserNotifications
import UsageKit

/// Per-account notification toggles (plus the one global peak toggle) —
/// every setter gates on the system permission through
/// `authorizeIfEnabling`, and every getter reads `notificationsRevision`
/// so a change re-evaluates the bindings that read UserDefaults. See the
/// type doc in `UsageModel.swift`.
extension UsageModel {
    // MARK: - Notification preferences (per account, except peak)

    func refreshNotificationAuthorization() async {
        let status = await NotificationScheduler.authorizationStatus()
        await MainActor.run { notificationsBlocked = status == .denied }
    }

    func preferences(for accountID: String) -> NotificationPreferences {
        NotificationPreferences(accountID: accountID)
    }

    /// Label passed to `NotificationScheduler` so a two-or-more-account
    /// install's notifications name the account they're about; a single
    /// account's copy stays exactly as it always read.
    func accountLabel(for accountID: String) -> String? {
        guard accounts.count > 1 else { return nil }
        return usage(for: accountID)?.account.displayName
    }

    func notificationsEnabled(for kind: UsageWindow.Kind, accountID: String) -> Bool {
        _ = notificationsRevision
        return preferences(for: accountID).isEnabled(for: kind)
    }

    func setNotificationsEnabled(_ enabled: Bool, for kind: UsageWindow.Kind, accountID: String) {
        // Never schedule a real notification off fabricated demo resets.
        let snapshot = isDemoMode ? nil : usage(for: accountID)?.snapshot
        let prefs = preferences(for: accountID)
        let label = accountLabel(for: accountID)
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
            prefs.setEnabled(enabled, for: kind)
            notificationsRevision += 1
            await NotificationScheduler.rescheduleResets(
                for: snapshot, accountID: accountID, accountLabel: label, preferences: prefs
            )
        }
    }

    // MARK: Smart notifications (per account, one toggle per `SmartAlert`)

    func smartAlertEnabled(_ alert: SmartAlert, for accountID: String) -> Bool {
        _ = notificationsRevision
        return preferences(for: accountID).isEnabled(alert)
    }

    /// One setter for the five families: same permission gate, same
    /// revision bump, and the one family with something to schedule right
    /// away (run-out) does so — the rest fire on detection at fetch time,
    /// so flipping their toggle has nothing to queue.
    func setSmartAlertEnabled(_ enabled: Bool, _ alert: SmartAlert, accountID: String) {
        // Never schedule a real notification off fabricated demo resets.
        let snapshot = isDemoMode ? nil : usage(for: accountID)?.snapshot
        let prefs = preferences(for: accountID)
        let label = accountLabel(for: accountID)
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            prefs.setEnabled(enabled, alert)
            notificationsRevision += 1
            guard alert == .runOut else { return }
            // Immediate scheduling uses the average rate (no history needed);
            // the next fetch refines it with the recent rate.
            let projections = snapshot.map {
                RunOutPredictor.averageProjections(for: $0, minimumUsedPct: RunOutPredictor.alertMinimumUsedPct)
            } ?? [:]
            await NotificationScheduler.rescheduleRunOuts(
                projections, accountID: accountID, accountLabel: label, preferences: prefs
            )
        }
    }

    func nearLimitThreshold(for accountID: String) -> Double {
        _ = notificationsRevision
        return preferences(for: accountID).nearLimitThreshold
    }

    func setNearLimitThreshold(_ threshold: Double, accountID: String) {
        preferences(for: accountID).nearLimitThreshold = threshold
        notificationsRevision += 1
    }

    // MARK: Peak-hours alerts (global — see `peakPreferences` above)

    var peakNotificationsEnabled: Bool {
        _ = notificationsRevision
        return peakPreferences.peakEnabled
    }

    func setPeakNotificationsEnabled(_ enabled: Bool) {
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            peakPreferences.peakEnabled = enabled
            notificationsRevision += 1
            await NotificationScheduler.reschedulePeakNotifications(preferences: peakPreferences)
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
}
