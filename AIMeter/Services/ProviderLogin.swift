import Foundation
import UsageKit

/// What a provider family's sign-in flow hands the model: its own typed
/// credentials. The one value that crosses from a Connect view to
/// `UsageModel.completeConnection` / `reconnect`, which build the
/// account for the login's family and store it through the account's
/// own source (`RefreshService.storeConnection`).
enum ProviderLogin {
    case claude(ClaudeCredentials)
    case codex(CodexCredentials)
    case copilot(CopilotCredentials)

    var providerID: String {
        switch self {
        case .claude: ClaudeProvider.providerID
        case .codex: CodexProvider.providerID
        case .copilot: CopilotProvider.providerID
        }
    }
}
