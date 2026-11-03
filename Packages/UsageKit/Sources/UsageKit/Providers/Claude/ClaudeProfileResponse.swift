import Foundation

/// Wire format of `GET https://api.anthropic.com/api/oauth/profile` —
/// undocumented, like the usage endpoint. Used to resolve the plan name
/// ("pro"/"max"/"ultra"), which the usage response doesn't carry, and the
/// account's own id (`account.uuid`), the one thing about a login that
/// is the same on every device it is signed in on. Nothing else of the
/// response (the name, the email, the rest of the organization) is
/// decoded: of the organization, only its rate-limit tier, which is what
/// tells Max from Ultra.
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

    struct Organization: Decodable {
        let rateLimitTier: String?

        enum CodingKeys: String, CodingKey {
            case rateLimitTier = "rate_limit_tier"
        }
    }

    let account: Account?
    let organization: Organization?

    /// The account's id, nil when the response has none (a shape change).
    var accountUUID: String? {
        guard let uuid = account?.uuid, !uuid.isEmpty else { return nil }
        return uuid
    }

    /// "max" wins when both flags are set, and a Max whose tier is the
    /// old 20x is "ultra": Anthropic renamed Max 5x to Max and Max 20x to
    /// Ultra on 2026-10-30, and the profile still says `has_claude_max`
    /// for both, told apart only by `rate_limit_tier`
    /// (`default_claude_max_5x`, `default_claude_max_20x`; measured
    /// 2026-11-03). A tier that names Ultra itself counts too, should the
    /// tier be renamed after the plan.
    var subscriptionType: String? {
        if account?.hasClaudeMax == true {
            let tier = organization?.rateLimitTier?.lowercased() ?? ""
            return tier.contains("max_20x") || tier.contains("ultra") ? "ultra" : "max"
        }
        if account?.hasClaudePro == true { return "pro" }
        return nil
    }
}
