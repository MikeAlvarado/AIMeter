import Foundation

/// An Atlassian Statuspage, the status page every provider this build
/// knows publishes (status.claude.com, status.openai.com,
/// githubstatus.com): one unauthenticated GET of `summary.json` carries
/// the overall indicator, every component's status and the unresolved
/// incidents. The one request in this package that carries nothing
/// about the user. Each provider names its two URLs
/// (`ClaudeStatusSource`, `CodexProvider`, `CopilotProvider`); the
/// reading is this.
public struct StatuspageSource: ServiceStatusSource {
    public let summaryEndpoint: URL
    /// The human page, for a banner with no incident link of its own.
    public let pageURL: URL

    private let transport: any HTTPTransport

    public init(summaryEndpoint: URL, pageURL: URL, transport: any HTTPTransport = URLSessionTransport()) {
        self.summaryEndpoint = summaryEndpoint
        self.pageURL = pageURL
        self.transport = transport
    }

    public func fetchStatus() async throws -> ServiceStatus {
        var request = URLRequest(url: summaryEndpoint)
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
    /// `incidents` and `scheduled_maintenances` are optional: OpenAI's
    /// page leaves them out entirely (measured 2026-10-20).
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
        let affected = (summary.components ?? [])
            .filter { $0.group != true && $0.status != "operational" }
            .map(\.name)
        // Statuspage lists only unresolved incidents in the summary, newest
        // first; a maintenance window shows up under its own key instead.
        let incident = summary.incidents?.first
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
        let components: [Component]?
        let incidents: [Incident]?
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
