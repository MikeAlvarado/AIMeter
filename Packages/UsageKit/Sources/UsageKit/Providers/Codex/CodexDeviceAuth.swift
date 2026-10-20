import Foundation

/// The Codex CLI's device-code sign-in (`codex login --device-auth`),
/// the one ChatGPT login that needs no localhost callback, so it works
/// from a phone: ask for a one-time code, show it with the page to type
/// it on, poll until the user has approved, then exchange the
/// authorization code the poll hands back. Rebuilt from
/// codex-rs/login/src/device_code_auth.rs. The user has to allow device
/// code login in ChatGPT's security settings first; the usercode request
/// still succeeds without it, and the approval page refuses the code.
public struct CodexDeviceAuth: Sendable {
    /// One pending sign-in: what the user is shown, and what the poll
    /// needs. The code expires in 15 minutes.
    public struct Code: Sendable, Equatable {
        public let userCode: String
        public let verificationURL: URL
        public let interval: TimeInterval
        public let expiresAt: Date?
        let deviceAuthID: String
    }

    static let usercodeEndpoint = URL(string: "https://auth.openai.com/api/accounts/deviceauth/usercode")!
    static let tokenEndpoint = URL(string: "https://auth.openai.com/api/accounts/deviceauth/token")!
    /// Where the user types the code.
    public static let verificationURL = URL(string: "https://auth.openai.com/codex/device")!
    /// The redirect the CLI registers for this flow; the exchange names
    /// it, nothing is ever sent there.
    static let redirectURI = "https://auth.openai.com/deviceauth/callback"
    static let defaultInterval: TimeInterval = 5

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func requestCode() async throws -> Code {
        var request = URLRequest(url: Self.usercodeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["client_id": CodexOAuthClient.clientID])
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            throw UsageError.httpError(statusCode: response.statusCode, body: CodexOAuthClient.body(data))
        }
        let decoded: UserCodeResponse
        do {
            decoded = try JSONDecoder().decode(UserCodeResponse.self, from: data)
        } catch {
            throw UsageError.invalidResponse("device code: \(error.localizedDescription)")
        }
        return Code(
            userCode: decoded.userCode,
            verificationURL: Self.verificationURL,
            interval: decoded.interval ?? Self.defaultInterval,
            expiresAt: decoded.expiresAt.flatMap(CodexCredentials.parseDate),
            deviceAuthID: decoded.deviceAuthID
        )
    }

    /// One poll: the login once the user has approved, nil while they
    /// haven't (the server answers 403 or 404 until then). Call again
    /// after `Code.interval`.
    public func poll(_ code: Code) async throws -> CodexCredentials? {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["device_auth_id": code.deviceAuthID, "user_code": code.userCode])
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200:
            break
        case 403, 404:
            return nil
        default:
            throw UsageError.httpError(statusCode: response.statusCode, body: CodexOAuthClient.body(data))
        }
        let approved: ApprovedResponse
        do {
            approved = try JSONDecoder().decode(ApprovedResponse.self, from: data)
        } catch {
            throw UsageError.invalidResponse("device approval: \(error.localizedDescription)")
        }
        return try await CodexOAuthClient(transport: transport).exchange(
            authorizationCode: approved.authorizationCode,
            codeVerifier: approved.codeVerifier,
            redirectURI: Self.redirectURI
        )
    }

    private struct UserCodeResponse: Decodable {
        let deviceAuthID: String
        let userCode: String
        /// The server spells the interval as a string ("5"); a number is
        /// accepted too.
        let interval: TimeInterval?
        let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case deviceAuthID = "device_auth_id"
            case userCode = "user_code"
            case usercode
            case interval
            case expiresAt = "expires_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            deviceAuthID = try container.decode(String.self, forKey: .deviceAuthID)
            userCode = try container.decodeIfPresent(String.self, forKey: .userCode)
                ?? container.decode(String.self, forKey: .usercode)
            if let number = try? container.decodeIfPresent(Double.self, forKey: .interval) {
                interval = number
            } else if let text = try? container.decodeIfPresent(String.self, forKey: .interval) {
                interval = TimeInterval(text.trimmingCharacters(in: .whitespaces))
            } else {
                interval = nil
            }
            expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        }
    }

    private struct ApprovedResponse: Decodable {
        let authorizationCode: String
        let codeVerifier: String

        enum CodingKeys: String, CodingKey {
            case authorizationCode = "authorization_code"
            case codeVerifier = "code_verifier"
        }
    }
}
