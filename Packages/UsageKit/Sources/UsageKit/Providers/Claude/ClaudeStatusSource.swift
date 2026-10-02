import Foundation

/// Claude's public status page, an Atlassian Statuspage at
/// status.claude.com (status.anthropic.com redirects there). One
/// unauthenticated GET of `summary.json` carries the overall indicator,
/// every component's status, and the unresolved incidents — see the
/// Claude provider's CLAUDE.md for the response shape and the fixtures.
public struct ClaudeStatusSource: ServiceStatusSource {
    public static let summaryEndpoint = URL(string: "https://status.claude.com/api/v2/summary.json")!
    /// The human page, for a banner with no incident link of its own.
    public static let pageURL = URL(string: "https://status.claude.com")!

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchStatus() async throws -> ServiceStatus {
        var request = URLRequest(url: Self.summaryEndpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            throw UsageError.httpError(statusCode: response.statusCode, body: String(data: data, encoding: .utf8))
        }
        return try Self.parse(data)
    }

    /// Pure mapping from a `summary.json` body — the testable half.
    public static func parse(_ data: Data, now: Date = Date()) throws -> ServiceStatus {
        let summary: Summary
        do {
            summary = try JSONDecoder().decode(Summary.self, from: data)
        } catch {
            throw UsageError.invalidResponse("status summary: \(error.localizedDescription)")
        }
        let indicator: ServiceStatus.Indicator = switch summary.status.indicator {
        case "none": .operational
        case "minor": .minor
        case "major": .major
        case "critical": .critical
        case "maintenance": .maintenance
        default: .unknown
        }
        let affected = summary.components
            .filter { $0.group != true && $0.status != "operational" }
            .map(\.name)
        // Statuspage lists only unresolved incidents in the summary, newest
        // first; a maintenance window shows up under its own key instead.
        let incident = summary.incidents.first
            ?? (indicator == .maintenance ? summary.scheduledMaintenances?.first : nil)
        return ServiceStatus(
            indicator: indicator,
            description: summary.status.description,
            affectedComponents: affected,
            incidentTitle: incident?.name,
            incidentURL: incident?.shortlink.flatMap(URL.init(string:)),
            checkedAt: now
        )
    }

    // MARK: - Wire shape (only the fields read)

    private struct Summary: Decodable {
        let status: Status
        let components: [Component]
        let incidents: [Incident]
        let scheduledMaintenances: [Incident]?

        enum CodingKeys: String, CodingKey {
            case status, components, incidents
            case scheduledMaintenances = "scheduled_maintenances"
        }
    }

    private struct Status: Decodable {
        let indicator: String
        let description: String
    }

    private struct Component: Decodable {
        let name: String
        let status: String
        let group: Bool?
    }

    private struct Incident: Decodable {
        let name: String
        let shortlink: String?
    }
}
