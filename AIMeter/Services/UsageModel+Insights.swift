import Foundation
import UsageKit

/// The readings the account card adds from the other accounts' figures
/// (`UsageInsights`). See the type doc in `UsageModel.swift`.
extension UsageModel {
    /// Another account of the same service with room, while this one is
    /// nearly out: "Work has 70% free" under its card.
    func room(for usage: AccountUsage) -> UsageInsights.Room? {
        UsageInsights.room(
            forUrgency: AccountOrder.urgency(of: usage.snapshot),
            providerID: usage.account.providerID,
            accountID: usage.account.accountID,
            among: accounts.map { ($0.account, $0.snapshot) }
        )
    }
}
