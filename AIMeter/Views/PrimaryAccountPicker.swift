#if os(macOS)
import SwiftUI
import UsageKit

/// "Account": which connected account the two glance surfaces read — the
/// status item and the notch island's wings (`Preferences.primaryAccountID`,
/// falling back to the first account). Offered only with two or more
/// accounts, once, in the Accounts tab's "Main account" card
/// (`MacAccountsSettingsPage`); the Menu bar and Notch island cards say
/// so under their previews (`MainAccountNote`) instead of repeating it.
/// A labeled menu like the "Style" row: the row of unlabeled segments it
/// replaced read as one more window picker.
struct PrimaryAccountPicker: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Account")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Picker("Account", selection: selection) {
                    ForEach(model.accounts, id: \.account.accountID) { usage in
                        Text(usage.account.displayName).tag(usage.account.accountID)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .tint(Theme.accent)
            }
            Text("The menu bar and the notch island show this account.")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    /// Writes through to `prefs.primaryAccountID`; reads through
    /// `UsageModel.primaryAccountUsage` so the menu always shows a
    /// connected account even if the stored id is stale (e.g. that account
    /// was disconnected elsewhere).
    private var selection: Binding<String> {
        Binding(
            get: { model.primaryAccountUsage(preferredID: prefs.primaryAccountID)?.account.accountID ?? ClaudeKeychainCredentialSource.legacyAccountID },
            set: { prefs.primaryAccountID = $0 }
        )
    }
}

/// Under the Menu bar and Notch island previews with two or more
/// accounts: where the account they show is chosen.
struct MainAccountNote: View {
    var body: some View {
        Label(String(localized: "Shows the main account, chosen in Accounts."), systemImage: "person.crop.circle")
            .font(Theme.caption)
            .foregroundStyle(Theme.inkSecondary)
    }
}
#endif
