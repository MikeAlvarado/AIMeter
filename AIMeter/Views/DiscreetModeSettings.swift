#if os(macOS)
import SwiftUI
import UsageKit

/// "Discreet mode" (Settings → Accounts, macOS): the one switch. Which
/// accounts it hides is each account's own setting
/// (`DiscreetAccountSettings`, on the account's page), so the general
/// card and the per-account one never repeat each other. The eye in the
/// popover's footer and ⌘⇧D flip the same switch.
struct DiscreetModeSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    static func isOffered(_ model: UsageModel) -> Bool {
        !model.accounts.isEmpty
    }

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Discreet mode"))
        Card {
            Toggle(isOn: $prefs.discreetMode) {
                Text("Discreet mode")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)
        }
        SectionFootnote(text: String(localized: "While it is on, the accounts marked for it in their own settings leave the menu bar and the notch island, and Claude Code's sessions leave the island: what a glance at your screen at work would otherwise see. The Dashboard and the widgets keep showing everything. The eye in the menu bar popover and ⌘⇧D turn it on and off."))
    }
}

/// On an account's page: whether discreet mode hides this account
/// (`Preferences.discreetAccountIDs`).
struct DiscreetAccountSettings: View {
    let accountID: String
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        SectionHeader(title: String(localized: "Discreet mode"))
        Card {
            Toggle(isOn: Binding(
                get: { prefs.discreetAccountIDs.contains(accountID) },
                set: { prefs.setDiscreet($0, accountID: accountID) }
            )) {
                Text("Hide in discreet mode")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)
        }
        SectionFootnote(text: String(localized: "While discreet mode is on, this account leaves the menu bar and the notch island. The mode itself is switched in Accounts, with the eye in the menu bar popover, or with ⌘⇧D."))
    }
}
#endif
