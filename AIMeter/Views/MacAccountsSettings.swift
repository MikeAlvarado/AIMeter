#if os(macOS)
import SwiftUI
import UsageKit

/// The Mac Settings window's Accounts tab, as the Mac's own account
/// settings are (Mail, Calendar, Internet Accounts): the accounts in a
/// list on the left with + and − under it, the one selected on the right
/// (`AccountSettingsCards`), and under the list what concerns them all:
/// the order, the account the menu bar and the island show, discreet
/// mode. Wider than the other tabs (`width`); both panes scroll on their
/// own, so neither the list nor a way back is ever out of sight. "+"
/// opens the Connect sheet over Settings and "−" asks before
/// disconnecting, as the page's own button does (`DisconnectConfirmation`).
/// Until 4.1 an account's settings sat under the tab's last section
/// behind a second "Account" menu, Disconnect at the very bottom (Mike,
/// 2026-10-22: "it makes no sense that you can't").
struct MacAccountsSettingsPage: View {
    /// The account shown on the right; nil (or one no longer connected)
    /// shows the first. Held by `MacSettingsView`, so General's
    /// Notifications rows can open an account here.
    @Binding var selection: String?
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @State private var connecting = false
    @State private var confirmingRemoval = false

    static let width: CGFloat = 760
    static let listWidth: CGFloat = 290

    private var selected: UsageModel.AccountUsage? {
        selection.flatMap { model.usage(for: $0) } ?? model.accounts.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    accountList
                    allAccounts
                }
                .padding(20)
            }
            .frame(width: Self.listWidth)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    detail
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Back to the top for each account.
            .id(selected?.id)
        }
        .frame(width: Self.width, height: MacSettingsView.scrollingHeight)
        .appBackground()
        .sheet(isPresented: $connecting) {
            ConnectAccountSheet()
                .withAppModels(model, prefs)
        }
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: String(localized: "Accounts"))
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.accounts) { usage in
                        Button {
                            selection = usage.id
                        } label: {
                            AccountListRow(usage: usage)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(usage.id == selected?.id ? Theme.accentWash : .clear)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(usage.id == selected?.id ? .isSelected : [])
                    }
                    if model.accounts.isEmpty {
                        Text("No account connected.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(8)
                    }
                }
            }
            // A connection in demo mode would land under the fabricated
            // accounts, and they can't be disconnected.
            if !model.isDemoMode {
                HStack(spacing: 6) {
                    Button {
                        connecting = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 18, height: 16)
                    }
                    .help(Text("Add Account…"))
                    .accessibilityLabel(Text("Add Account…"))
                    Button {
                        confirmingRemoval = true
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 18, height: 16)
                    }
                    .disabled(selected == nil)
                    .help(Text("Disconnect"))
                    .accessibilityLabel(Text("Disconnect"))
                    .disconnectConfirmation(accountID: selected?.id ?? "", isPresented: $confirmingRemoval) {
                        selection = nil
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var allAccounts: some View {
        if AccountOrderToggle.isOffered(model) {
            SettingsGap()
            Card {
                AccountOrderToggle()
            }
            SectionFootnote(text: AccountOrderToggle.footnote)
            SettingsGap()
            SectionHeader(title: String(localized: "Menu bar and island"))
            Card {
                PrimaryAccountPicker()
            }
        }
        if DiscreetModeSettings.isOffered(model) {
            SettingsGap()
            DiscreetModeSettings()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selected {
            HStack(spacing: 10) {
                ProviderIdentityView(
                    name: selected.account.displayName,
                    iconSize: 32,
                    iconCornerRadius: 8,
                    font: .title3.weight(.semibold),
                    nameColor: Theme.ink,
                    planName: selected.snapshot?.planName,
                    icon: selected.account.icon
                )
                Spacer()
            }
            Text(verbatim: ProviderCatalog.displayName(for: selected.account.providerID))
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
            SettingsGap()
            AccountSettingsCards(accountID: selected.id, onDisconnect: { selection = nil })
        } else {
            SectionHeader(title: String(localized: "Accounts"))
            Card {
                DisconnectedPrompt(buttonLabel: "Connect an account", verticalPadding: 10) {
                    connecting = true
                }
            }
        }
    }
}
#endif
