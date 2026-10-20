#if os(macOS)
import SwiftUI
import UsageKit

/// "Discreet mode" (Settings → General, macOS): the switch, and under it
/// which accounts leave the menu bar and the notch island while it is on
/// (`UsageModel.glanceAccounts`). Claude Code's sessions leave the island
/// with them. The eye in the popover's footer and ⌘⇧D flip the same
/// switch.
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
            Divider().overlay(Theme.track)
            Text("Accounts hidden while it is on")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
            ForEach(model.accounts) { usage in
                Toggle(isOn: Binding(
                    get: { prefs.discreetAccountIDs.contains(usage.id) },
                    set: { prefs.setDiscreet($0, accountID: usage.id) }
                )) {
                    HStack(spacing: 8) {
                        ProviderIdentityView(
                            name: usage.account.displayName,
                            iconSize: 20,
                            iconCornerRadius: 5,
                            font: Theme.rowTitle,
                            nameColor: Theme.ink,
                            planName: nil,
                            icon: usage.account.icon
                        )
                    }
                }
                .tint(Theme.accent)
            }
        }
        SectionFootnote(text: String(localized: "While discreet mode is on, the accounts marked here leave the menu bar and the notch island, and Claude Code's sessions leave the island: what a glance at your screen at work would otherwise see. The Dashboard and the widgets keep showing everything. The eye in the menu bar popover and ⌘⇧D turn it on and off."))
    }
}
#endif
