import Foundation

/// A provider family's published service health — "is the service itself
/// having an incident" — as distinct from any one account's usage. It is
/// per provider, not per account: two Claude accounts share one status.
///
/// The app reads it to tell an outage apart from an account problem: an
/// HTTP 5xx or a rate limit during an incident is the provider's fault,
/// and the UI can say so instead of showing a raw body in red as if the
/// account were broken.
public struct ServiceStatus: Codable, Equatable, Sendable {
    /// Statuspage's overall indicator, normalized. `unknown` is what the
    /// app holds when the status could not be fetched or parsed — and it
    /// is treated exactly like `operational`: nothing is ever announced
    /// that was not confirmed.
    public enum Indicator: String, Codable, Sendable {
        case operational, minor, major, critical, maintenance, unknown
    }

    public let indicator: Indicator
    /// The page's own one-line summary ("All Systems Operational",
    /// "Partial System Outage"). Comes from the API in its own language and
    /// is shown verbatim.
    public let description: String
    /// Component names whose status is not `operational`, in page order.
    /// Names are the page's own and are never translated or matched on.
    public let affectedComponents: [String]
    /// The most recent unresolved incident (or scheduled maintenance when
    /// the indicator is `maintenance`), if any.
    public let incidentTitle: String?
    /// Where to read more — the incident's own page when there is one.
    public let incidentURL: URL?
    public let checkedAt: Date

    public init(
        indicator: Indicator,
        description: String,
        affectedComponents: [String] = [],
        incidentTitle: String? = nil,
        incidentURL: URL? = nil,
        checkedAt: Date = Date()
    ) {
        self.indicator = indicator
        self.description = description
        self.affectedComponents = affectedComponents
        self.incidentTitle = incidentTitle
        self.incidentURL = incidentURL
        self.checkedAt = checkedAt
    }

    /// True when the provider itself reports a problem. `unknown` is not
    /// degraded — see `Indicator`.
    public var isDegraded: Bool {
        switch indicator {
        case .operational, .unknown: false
        case .minor, .major, .critical, .maintenance: true
        }
    }
}

/// Where a provider family publishes its health. A provider without a
/// status page simply has no source (`ProviderCatalog.statusSource(for:)`
/// returns nil) and the app shows nothing for it.
public protocol ServiceStatusSource: Sendable {
    func fetchStatus() async throws -> ServiceStatus
}
