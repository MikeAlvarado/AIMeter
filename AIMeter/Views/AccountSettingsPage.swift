import SwiftUI
import UsageKit

/// One account's own settings and nothing general: its name and icon,
/// its notifications, on iOS its Live Activity, on the Mac whether
/// discreet mode hides it, and disconnecting it. Every general setting
/// lives in Settings' other sections, so nothing is in two places
/// (Mike's rule, 2026-10-19). Shown on the account's page
/// (`AccountSettingsPage`, pushed from Settings' account list and from
/// the end of Provider Detail) and in the Mac Settings window's Accounts
/// tab under its account picker (`MacAccountsSettingsPage`).
struct AccountSettingsCards: View {
    let accountID: String
    /// Called once the account is disconnected, so a pushed page can pop
    /// and the Mac's tab can pick another account.
    var onDisconnect: (() -> Void)? = nil

    @Environment(UsageModel.self) private var model
    @State private var showingRename = false
    @State private var renameDraft = ""
    @State private var showingIconPicker = false

    private var usage: UsageModel.AccountUsage? {
        model.usage(for: accountID)
    }

    /// The nickname, or the provider's name while the account is gone
    /// (the page is mid-dismiss after a disconnect).
    private var accountName: String {
        usage?.account.displayName ?? ProviderCatalog.displayName(for: ProviderCatalog.defaultProviderID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.isDemoMode {
                // The discoverable route to the same rename and icon the
                // Dashboard header's context menu offers — a context menu
                // announces nothing about itself.
                SectionHeader(title: String(localized: "Account"))
                Card {
                    Button {
                        renameDraft = usage?.account.displayName ?? ""
                        showingRename = true
                    } label: {
                        HStack(spacing: 12) {
                            Text("Name")
                                .font(Theme.rowTitle)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(accountName)
                                .font(.body)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                            Image(systemName: "pencil")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Rename account"))
                    .accessibilityValue(Text(accountName))
                    Divider().overlay(Theme.track)
                    Button {
                        showingIconPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Text("Icon")
                                .font(Theme.rowTitle)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            ProviderMark(size: 24, cornerRadius: 6, icon: usage?.account.icon)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Change icon"))
                }
                SectionFootnote(text: String(localized: "Shown on the dashboard, in widgets, and in notification titles."))
                SettingsGap()
            }

            SectionHeader(title: String(localized: "Notifications"))
            NotificationTogglesCard(accountID: accountID)
            SectionFootnote(text: String(localized: "A local notification fires when the selected usage window resets."))

            SettingsGap()
            SectionHeader(title: String(localized: "Smart notifications"))
            SmartNotificationTogglesCard(accountID: accountID)
            SectionFootnote(text: SmartNotificationTogglesCard.footnote)

            #if os(iOS)
            SettingsGap()
            SectionHeader(title: String(localized: "Live Activity"))
            LiveActivityCard(accountID: accountID)
            SectionFootnote(text: String(localized: "Shows this account's session countdown on the Lock Screen and Dynamic Island while a session is running. Off by default. It updates whenever AIMeter or its widgets happen to refresh, not instantly, since there's no server to push updates."))
            #endif

            #if os(macOS)
            SettingsGap()
            DiscreetAccountSettings(accountID: accountID)
            #endif

            if !model.isDemoMode {
                SettingsGap()
                Button(role: .destructive) {
                    model.disconnect(accountID: accountID)
                    onDisconnect?()
                } label: {
                    Text("Disconnect \(accountName)")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
            }
        }
        .sheet(isPresented: $showingIconPicker) {
            AccountIconPicker(accountID: accountID)
        }
        .renameAccountAlert(for: accountID, isPresented: $showingRename, name: $renameDraft)
    }
}

/// The account's settings as a pushed page: from the Settings list's
/// account rows (iOS) and from Provider Detail's "Account settings" row
/// (both platforms, in the Dashboard's navigation stack).
struct AccountSettingsPage: View {
    let accountID: String

    @Environment(UsageModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            AccountSettingsCards(accountID: accountID, onDisconnect: { dismiss() })
                .padding(20)
        }
        .appBackground()
        .navigationTitle(model.usage(for: accountID)?.account.displayName ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// The row at the end of Provider Detail that leads to the page above:
/// the data screen keeps no setting of its own.
struct AccountSettingsLink: View {
    let accountID: String

    var body: some View {
        Card {
            NavigationLink {
                AccountSettingsPage(accountID: accountID)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Account settings")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        SectionFootnote(text: String(localized: "Its notifications, name and icon, and disconnecting."))
    }
}
