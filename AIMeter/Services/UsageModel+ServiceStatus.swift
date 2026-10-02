import Foundation
import UsageKit

/// The provider's own service health, alongside the accounts' usage. One
/// check per provider family per refresh sweep, never per account, and
/// never more often than `serviceStatusMinimumInterval`; the result is a
/// `ServiceStatus` per `providerID` (see `serviceStatus`). A failed check
/// leaves the last known status in place for a while and then drops it —
/// nothing is ever announced that wasn't confirmed, so "unknown" renders
/// as nothing at all.
extension UsageModel {
    /// Floor between two checks of the same provider's page. `nonisolated`
    /// (plain constants, like `AppConfig`) so the default argument below
    /// can read it from any context.
    nonisolated static let serviceStatusMinimumInterval: TimeInterval = 5 * 60
    /// How long a last-known status is still shown after checks start
    /// failing. Beyond this the banner would be asserting something the
    /// app hasn't been able to confirm for half an hour.
    nonisolated static let serviceStatusMaxAge: TimeInterval = 30 * 60

    /// Pure throttle rule, so the tests can pin it without a clock.
    nonisolated static func isServiceStatusDue(
        lastChecked: Date?,
        now: Date,
        minimumInterval: TimeInterval = serviceStatusMinimumInterval
    ) -> Bool {
        guard let lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= minimumInterval
    }

    /// Called from Settings when the toggle changes; off clears what's
    /// shown immediately rather than waiting for the next sweep.
    func setChecksServiceStatus(_ enabled: Bool) {
        checksServiceStatus = enabled
        guard !enabled else { return }
        for providerID in serviceStatus.keys {
            serviceStatusStore?.clear(for: providerID)
        }
        serviceStatus = [:]
        serviceStatusCheckedAt = [:]
    }

    /// Seeds `serviceStatus` from the App Group so the popover and
    /// dashboard show the last confirmed state before the first check of
    /// this launch lands. Statuses older than `serviceStatusMaxAge` are
    /// not resurrected.
    func loadStoredServiceStatus() {
        guard checksServiceStatus, let store = serviceStatusStore else { return }
        for providerID in Set(accounts.map(\.account.providerID)) {
            guard let stored = store.status(for: providerID),
                  Date().timeIntervalSince(stored.checkedAt) <= Self.serviceStatusMaxAge else { continue }
            serviceStatus[providerID] = stored
        }
    }

    /// One check per connected provider family that is due, concurrently
    /// with (and independent of) the accounts' own fetches.
    func refreshServiceStatus(now: Date = Date()) async {
        guard !isDemoMode, checksServiceStatus else { return }
        let due = Set(accounts.map(\.account.providerID)).filter {
            Self.isServiceStatusDue(lastChecked: serviceStatusCheckedAt[$0], now: now)
        }
        guard !due.isEmpty else { return }
        for providerID in due { serviceStatusCheckedAt[providerID] = now }
        await withTaskGroup(of: (String, ServiceStatus?).self) { group in
            for providerID in due {
                guard let source = statusSource(for: providerID) else { continue }
                group.addTask { (providerID, try? await source.fetchStatus()) }
            }
            for await (providerID, status) in group {
                apply(status, for: providerID, now: now)
            }
        }
    }

    private func statusSource(for providerID: String) -> (any ServiceStatusSource)? {
        if let cached = serviceStatusSources[providerID] { return cached }
        guard let source = ProviderCatalog.statusSource(for: providerID) else { return nil }
        serviceStatusSources[providerID] = source
        return source
    }

    /// A fetched status replaces the last one; a failed check keeps it
    /// until it's too old to trust, then drops it. Internal so the tests
    /// can drive the aging rule without a transport.
    func apply(_ status: ServiceStatus?, for providerID: String, now: Date) {
        if let status {
            serviceStatus[providerID] = status
            serviceStatusStore?.save(status, for: providerID)
        } else if let last = serviceStatus[providerID],
                  now.timeIntervalSince(last.checkedAt) > Self.serviceStatusMaxAge {
            serviceStatus[providerID] = nil
            serviceStatusStore?.clear(for: providerID)
        }
    }

    // MARK: - What the surfaces read

    /// The incident the dashboard banner and the menu bar popover show:
    /// the most severe degraded status among the connected providers, nil
    /// on a normal day (and in demo mode, whose data is fabricated).
    var activeIncident: (providerID: String, status: ServiceStatus)? {
        guard !isDemoMode else { return nil }
        let order = accounts.map(\.account.providerID)
        return serviceStatus
            .filter { $0.value.isDegraded }
            .sorted { lhs, rhs in
                let l = Self.severity(lhs.value.indicator), r = Self.severity(rhs.value.indicator)
                if l != r { return l > r }
                return (order.firstIndex(of: lhs.key) ?? .max) < (order.firstIndex(of: rhs.key) ?? .max)
            }
            .first
            .map { ($0.key, $0.value) }
    }

    private static func severity(_ indicator: ServiceStatus.Indicator) -> Int {
        switch indicator {
        case .critical: 4
        case .major: 3
        case .minor: 2
        case .maintenance: 1
        case .operational, .unknown: 0
        }
    }

    /// The one line `UsageStatusFooter` adds under a failing account's raw
    /// error while its provider reports an incident — and only then: not
    /// when the account is fine, not offline (that's the device's network,
    /// not their outage), not for a dead login (an incident doesn't
    /// invalidate credentials).
    func incidentNote(for usage: AccountUsage) -> String? {
        guard usage.lastError != nil, !usage.isOffline, !usage.needsReauthentication,
              let status = serviceStatus[usage.account.providerID], status.isDegraded else { return nil }
        let name = ProviderCatalog.displayName(for: usage.account.providerID)
        let what = status.incidentTitle ?? status.description
        return String(localized: "\(name) reports an incident: \(what)")
    }

    /// Provider Detail's always-on footnote under the rate-limit card —
    /// the one place the status is shown even when everything is fine, so
    /// the user can see the check is happening and how fresh it is.
    func serviceStatusFootnote(for providerID: String, now: Date = Date()) -> String? {
        guard !isDemoMode, let status = serviceStatus[providerID] else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let ago = formatter.localizedString(for: status.checkedAt, relativeTo: now)
        return String(localized: "Service status: \(status.description) · checked \(ago)")
    }
}
