import Foundation

/// Typed errors surfaced by UsageKit. UI layers decide presentation.
public enum UsageError: Error, Equatable, Sendable {
    /// No stored credentials were found for the provider.
    case credentialsNotFound(String)
    /// The token is expired and cannot be refreshed from this device.
    case tokenExpired
    /// The provider rejected the credentials (HTTP 401 after any refresh attempt).
    case notAuthenticated
    /// The provider is rate-limiting us (HTTP 429). `body` is the raw
    /// response text, when there was one.
    case rateLimited(retryAfter: TimeInterval?, body: String?)
    case httpError(statusCode: Int, body: String?)
    /// The response arrived but could not be interpreted.
    case invalidResponse(String)
    case storage(String)
}

extension UsageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .credentialsNotFound(let detail):
            return String(localized: "No credentials found: \(detail)", bundle: .module)
        case .tokenExpired:
            return String(localized: "The access token has expired.", bundle: .module)
        case .notAuthenticated:
            return String(localized: "The provider rejected the credentials.", bundle: .module)
        case .rateLimited(let retryAfter, let body):
            var text = retryAfter.map {
                String(localized: "Rate limited; retry after \(Int($0)) seconds.", bundle: .module)
            } ?? String(localized: "Rate limited by the provider.", bundle: .module)
            if let body {
                text += "\n\(body)"
            }
            return text
        case .httpError(let statusCode, let body):
            if let body {
                return String(localized: "The provider returned HTTP \(statusCode): \(body)", bundle: .module)
            }
            return String(localized: "The provider returned HTTP \(statusCode).", bundle: .module)
        case .invalidResponse(let detail):
            return String(localized: "Unexpected response: \(detail)", bundle: .module)
        case .storage(let detail):
            return String(localized: "Storage error: \(detail)", bundle: .module)
        }
    }
}
