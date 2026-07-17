import Foundation

/// Typed errors surfaced by UsageKit. UI layers decide presentation.
public enum UsageError: Error, Equatable, Sendable {
    /// No stored credentials were found for the provider.
    case credentialsNotFound(String)
    /// The token is expired and cannot be refreshed from this device.
    case tokenExpired
    /// The provider rejected the credentials (HTTP 401 after any refresh attempt).
    case notAuthenticated
    /// The provider is rate-limiting us (HTTP 429).
    case rateLimited(retryAfter: TimeInterval?)
    case httpError(statusCode: Int)
    /// The response arrived but could not be interpreted.
    case invalidResponse(String)
    case storage(String)
}

extension UsageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .credentialsNotFound(let detail):
            return "No credentials found: \(detail)"
        case .tokenExpired:
            return "The access token has expired."
        case .notAuthenticated:
            return "The provider rejected the credentials."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited; retry after \(Int(retryAfter)) seconds."
            }
            return "Rate limited by the provider."
        case .httpError(let statusCode):
            return "The provider returned HTTP \(statusCode)."
        case .invalidResponse(let detail):
            return "Unexpected response: \(detail)"
        case .storage(let detail):
            return "Storage error: \(detail)"
        }
    }
}
