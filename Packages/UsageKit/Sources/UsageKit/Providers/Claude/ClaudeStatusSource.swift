import Foundation

/// Claude's public status page, an Atlassian Statuspage at
/// status.claude.com (status.anthropic.com redirects there), read by
/// `StatuspageSource` — see the Claude provider's CLAUDE.md for the
/// response shape and the fixtures.
public struct ClaudeStatusSource: ServiceStatusSource {
    public static let summaryEndpoint = URL(string: "https://status.claude.com/api/v2/summary.json")!
    /// The human page, for a banner with no incident link of its own.
    public static let pageURL = URL(string: "https://status.claude.com")!

    private let page: StatuspageSource

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        page = StatuspageSource(summaryEndpoint: Self.summaryEndpoint, pageURL: Self.pageURL, transport: transport)
    }

    public func fetchStatus() async throws -> ServiceStatus {
        try await page.fetchStatus()
    }

    /// Pure mapping from a `summary.json` body — the testable half.
    public static func parse(_ data: Data, now: Date = Date()) throws -> ServiceStatus {
        try StatuspageSource.parse(data, now: now)
    }
}
