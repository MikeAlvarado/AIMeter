#if os(macOS)
import SwiftUI
import UsageKit

/// "Discreet mode" (Settings → Accounts, under the list, macOS): the one
/// switch, and under it which accounts it hides, or that none is marked
/// yet. Each account is marked on its own settings
/// (`DiscreetAccountSettings`, Mike's call, 2026-10-22), and the line here
/// says so, so turning the switch on with nothing marked never looks like
/// it did nothing. Discreet Mode in the popover's footer and ⌘⇧D flip the
/// same switch.
struct DiscreetModeSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    static func isOffered(_ model: UsageModel) -> Bool {
        !model.accounts.isEmpty
    }

    private var hiddenNames: [String] {
        model.accounts
            .filter { prefs.discreetAccountIDs.contains($0.id) }
            .map(\.account.displayName)
    }

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Discreet mode"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                Toggle(isOn: $prefs.discreetMode) {
                    Text("Discreet mode")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)
                Divider().overlay(Theme.track)
                Group {
                    if hiddenNames.isEmpty {
                        Text("No account is marked to hide yet: turn on Hide in discreet mode in an account's settings.")
                    } else {
                        Text("Hides \(hiddenNames.formatted(.list(type: .and)))")
                    }
                }
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        SectionFootnote(text: String(localized: "While it is on, the accounts marked for it leave the menu bar and the notch island, and Claude Code's sessions leave the island: what a glance at your screen at work would otherwise see. The Dashboard and the widgets keep showing everything. Discreet Mode in the menu bar popover and ⌘⇧D turn it on and off."))
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
        SectionFootnote(text: String(localized: "While discreet mode is on, this account leaves the menu bar and the notch island. The switch is under the accounts list, in the menu bar popover and on ⌘⇧D."))
    }
}
#endif
