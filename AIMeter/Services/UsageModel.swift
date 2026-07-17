import Foundation
import Observation
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
        } catch {
            lastError = error.localizedDescription
        }
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

    func notificationsEnabled(for kind: UsageWindow.Kind) -> Bool {
        preferences.isEnabled(for: kind)
    }

    func setNotificationsEnabled(_ enabled: Bool, for kind: UsageWindow.Kind) {
        preferences.setEnabled(enabled, for: kind)
        let snapshot = self.snapshot
        Task {
            if enabled {
                _ = await NotificationScheduler.requestAuthorization()
            }
            await NotificationScheduler.reschedule(for: snapshot, preferences: preferences)
        }
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
