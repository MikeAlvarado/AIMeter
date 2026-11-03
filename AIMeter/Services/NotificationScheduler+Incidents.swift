import Foundation
import UserNotifications
import UsageKit

/// "Notify about incidents": one notification per incident of a connected
/// service, from the status check every sweep already runs (see "Service
/// status" in the repo-root CLAUDE.md), taken back once the page reports
/// the service operational again. Identifiers are `incident.<providerID>`:
/// one per family, so a new incident replaces the last one's notice.
extension NotificationScheduler {
    static let incidentPrefix = "incident."

    /// What a fresh status asks of the notification, given the incident
    /// already announced for that family. Pure, so the tests pin it.
    enum IncidentAlert: Equatable {
        /// A new incident: announce it under this key.
        case announce(String)
        /// The service is back: take the notice back.
        case withdraw
        case none
    }

    /// Only an outage is announced (minor, major, critical): scheduled
    /// maintenance is planned, and an unknown status is no news at all,
    /// as everywhere else.
    nonisolated static func incidentAlert(for status: ServiceStatus, announced: String?) -> IncidentAlert {
        switch status.indicator {
        case .minor, .major, .critical:
            let key = status.incidentTitle ?? status.description
            return key == announced ? .none : .announce(key)
        case .operational, .maintenance:
            return announced == nil ? .none : .withdraw
        case .unknown:
            return .none
        }
    }

    static func notifyIncident(providerID: String, providerName: String, status: ServiceStatus) async {
        guard await canDeliver() else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(providerName) reports an incident")
        content.body = status.incidentTitle ?? status.description
        content.sound = .default
        let request = UNNotificationRequest(identifier: incidentPrefix + providerID, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func withdrawIncident(providerID: String) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [incidentPrefix + providerID])
        center.removePendingNotificationRequests(withIdentifiers: [incidentPrefix + providerID])
    }
}
