import Foundation

/// GitHub's OAuth device flow, the documented one, with the OAuth App
/// id Copilot's own editor plug-ins and CLI sign in with: ask for a
/// one-time code, show it with github.com/login/device, poll until the
/// user has approved. The token it mints is what the Copilot quota
/// endpoint accepts; one minted for a third party's own OAuth App is not
/// (there is no public registration for that endpoint). No scope is
/// asked for: the endpoint needs none.
public struct CopilotDeviceAuth: Sendable {
    /// One pending sign-in: what the user is shown, and what the poll
    /// needs.
    public struct Code: Sendable, Equatable {
        public let userCode: String
        public let verificationURL: URL
        public let interval: TimeInterval
        public let expiresAt: Date
        let deviceCode: String
    }

    /// What one poll found.
    public enum Poll: Sendable, Equatable {
        /// Not approved yet; poll again after `interval` (GitHub raises it
        /// when polled too fast).
        case pending(interval: TimeInterval)
        case authorized(CopilotCredentials)
    }

    static let codeEndpoint = URL(string: "https://github.com/login/device/code")!
    static let tokenEndpoint = URL(string: "https://github.com/login/oauth/access_token")!
    /// Copilot's OAuth App (VS Code's Copilot, the Copilot CLI, opencode).
    static let clientID = "Iv1.b507a08c87ecfe98"
    /// No scope at all: the quota endpoint needs none (measured
    /// 2026-10-20 with a token GitHub granted no scope), and its answer
    /// carries the user id, so nothing else is ever read. A token with no
    /// scope reaches nothing private on GitHub.
    public static let scope = ""
    static let defaultInterval: TimeInterval = 5

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func requestCode(now: Date = Date()) async throws -> Code {
        let (data, response) = try await post(Self.codeEndpoint, [
            ("client_id", Self.clientID),
        ])
        guard response.statusCode == 200 else {
            throw UsageError.httpError(statusCode: response.statusCode, body: CodexOAuthClient.body(data))
        }
        let decoded: CodeResponse
        do {
            decoded = try JSONDecoder().decode(CodeResponse.self, from: data)
        } catch {
            throw UsageError.invalidResponse("device code: \(error.localizedDescription)")
        }
        return Code(
            userCode: decoded.userCode,
            verificationURL: URL(string: decoded.verificationUri) ?? URL(string: "https://github.com/login/device")!,
            interval: decoded.interval ?? Self.defaultInterval,
            expiresAt: now.addingTimeInterval(decoded.expiresIn ?? 900),
            deviceCode: decoded.deviceCode
        )
    }

    /// One poll. A code the user declined or let expire is a rejected
    /// login (`notAuthenticated`); anything else GitHub reports is shown.
    public func poll(_ code: Code) async throws -> Poll {
        let (data, response) = try await post(Self.tokenEndpoint, [
            ("client_id", Self.clientID),
            ("device_code", code.deviceCode),
            ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
        ])
        guard response.statusCode == 200 else {
            throw UsageError.httpError(statusCode: response.statusCode, body: CodexOAuthClient.body(data))
        }
        let decoded: TokenResponse
        do {
            decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw UsageError.invalidResponse("device token: \(error.localizedDescription)")
        }
        if let token = decoded.accessToken, !token.isEmpty {
            return .authorized(CopilotCredentials(accessToken: token))
        }
        switch decoded.error {
        case "authorization_pending":
            return .pending(interval: code.interval)
        case "slow_down":
            return .pending(interval: decoded.interval ?? code.interval + 5)
        case "expired_token", "access_denied":
            throw UsageError.notAuthenticated
        default:
            throw UsageError.invalidResponse(decoded.errorDescription ?? decoded.error ?? "no token in response")
        }
    }

    private func post(_ url: URL, _ parameters: [(String, String)]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(CodexOAuthClient.formEncoded(parameters).utf8)
        return try await transport.send(request)
    }

    private struct CodeResponse: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let expiresIn: Double?
        let interval: Double?

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationUri = "verification_uri"
            case expiresIn = "expires_in"
            case interval
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let error: String?
        let errorDescription: String?
        let interval: Double?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case error
            case errorDescription = "error_description"
            case interval
        }
    }
}
