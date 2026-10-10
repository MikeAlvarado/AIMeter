#if os(macOS)
import SwiftUI
import UsageKit

/// "Account": which connected account the two glance surfaces read — the
/// status item and the notch island's wings (`Preferences.primaryAccountID`,
/// falling back to the first account). Offered only with two or more
/// accounts, in both of their Settings cards, as a labeled menu like the
/// "Style" row: the row of unlabeled segments it replaces sat right above
/// the equally unlabeled window segments and read as one more window
/// picker, not as the choice of account it was — and it lived only in
/// the Menu bar card, whose icon the island hides.
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
#endif
