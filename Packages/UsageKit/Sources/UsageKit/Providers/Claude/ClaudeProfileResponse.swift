import Foundation

/// Wire format of `GET https://api.anthropic.com/api/oauth/profile` —
/// undocumented, like the usage endpoint. Used to resolve the plan name
/// ("pro"/"max"), which the usage response doesn't carry, and the
/// account's own id (`account.uuid`), the one thing about a login that
/// is the same on every device it is signed in on. Nothing else of the
/// response (the name, the email, the organization) is decoded.
struct ClaudeProfileResponse: Decodable {
    struct Account: Decodable {
        let uuid: String?
        let hasClaudePro: Bool?
        let hasClaudeMax: Bool?

        enum CodingKeys: String, CodingKey {
            case uuid
            case hasClaudePro = "has_claude_pro"
            case hasClaudeMax = "has_claude_max"
        }
    }

    let account: Account?

    /// The account's id, nil when the response has none (a shape change).
    var accountUUID: String? {
        guard let uuid = account?.uuid, !uuid.isEmpty else { return nil }
        return uuid
    }

    /// "max" wins when both flags are set.
    var subscriptionType: String? {
        if account?.hasClaudeMax == true { return "max" }
        if account?.hasClaudePro == true { return "pro" }
        return nil
    }
}
