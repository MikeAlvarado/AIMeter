import Foundation
import UsageKit

/// Discreet mode (macOS, `Preferences.discreetMode`): what the Mac's
/// glance surfaces show while it is on. The status item, the popover
/// and the notch island draw from `glanceAccounts`, so the accounts
/// marked for it (`Preferences.discreetAccountIDs`) leave all three at
/// once; the Dashboard and the widgets keep `accounts`. Pure over the
/// model's rows and the preferences, so the rule is tested here.
extension UsageModel {
    /// The accounts the glance surfaces show: all of them, or in discreet
    /// mode those not marked for it, in the same order.
    func glanceAccounts(_ prefs: PreferencesModel) -> [AccountUsage] {
        guard prefs.discreetMode else { return accounts }
        return accounts.filter { !prefs.discreetAccountIDs.contains($0.id) }
    }

    /// `primaryAccountUsage` among those: the chosen one while it shows,
    /// else the first that does. The chosen account stays chosen
    /// (`primaryAccountID` is not rewritten), so it is back when the mode
    /// goes off.
    func glancePrimary(_ prefs: PreferencesModel) -> AccountUsage? {
        let shown = glanceAccounts(prefs)
        if let id = prefs.primaryAccountID, let match = shown.first(where: { $0.id == id }) {
            return match
        }
        return shown.first
    }
}
