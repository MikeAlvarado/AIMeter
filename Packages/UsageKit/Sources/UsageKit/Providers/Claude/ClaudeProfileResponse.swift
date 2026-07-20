import Foundation

/// Wire format of `GET https://api.anthropic.com/api/oauth/profile` —
/// undocumented, like the usage endpoint. Only used to resolve the plan
/// name ("pro"/"max") when the stored credentials don't carry one: the
/// in-app OAuth exchange doesn't return a subscription type.
struct ClaudeProfileResponse: Decodable {
    struct Account: Decodable {
        let hasClaudePro: Bool?
        let hasClaudeMax: Bool?

        enum CodingKeys: String, CodingKey {
            case hasClaudePro = "has_claude_pro"
            case hasClaudeMax = "has_claude_max"
        }
    }

    let account: Account?

    /// "max" wins when both flags are set.
    var subscriptionType: String? {
        if account?.hasClaudeMax == true { return "max" }
        if account?.hasClaudePro == true { return "pro" }
        return nil
    }
}
