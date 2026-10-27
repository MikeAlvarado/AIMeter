import SwiftUI
import UsageKit

/// One account's own settings and nothing general: signing in again when
/// its login stopped working, its name and icon, its notifications, on
/// iOS its Live Activity, on the Mac whether discreet mode hides it, and
/// disconnecting it. Every general setting
/// lives in Settings' other sections, so nothing is in two places
/// (Mike's rule, 2026-10-19). Shown on the account's page
/// (`AccountSettingsPage`, pushed from Settings' account list and from
/// the end of Provider Detail) and in the Mac Settings window's Accounts
/// tab's detail pane (`MacAccountsSettingsPage`).
struct AccountSettingsCards: View {
    let accountID: String
    /// Called once the account is disconnected, so a pushed page can pop
    /// and the Mac's tab can pick another account.
    var onDisconnect: (() -> Void)? = nil

    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @State private var showingRename = false
    @State private var renameDraft = ""
    @State private var showingIconPicker = false
    @State private var confirmingDisconnect = false
    @State private var reconnecting: ConnectedAccount?

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
            // A login that stopped working comes first: Settings' row for
            // the account says "Sign in again", and this is where it leads.
            if let usage, usage.needsReauthentication, !model.isDemoMode {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(String(localized: "Sign-in expired. Usage can't refresh."), systemImage: "exclamationmark.triangle")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                        Button {
                            reconnecting = usage.account
                        } label: {
                            Text("Sign in again")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                SettingsGap()
            }
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
                // Disconnecting deletes the account's history and alerts
                // on this device, so it asks first.
                Button(role: .destructive) {
                    confirmingDisconnect = true
                } label: {
                    Text("Disconnect \(accountName)")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .disconnectConfirmation(accountID: accountID, isPresented: $confirmingDisconnect) {
                    onDisconnect?()
                }
            }
        }
        .sheet(isPresented: $showingIconPicker) {
            AccountIconPicker(accountID: accountID)
                .withAppModels(model, prefs)
        }
        .sheet(item: $reconnecting) { account in
            ConnectAccountSheet(reconnecting: account)
                .withAppModels(model, prefs)
        }
        .renameAccountAlert(for: accountID, isPresented: $showingRename, name: $renameDraft)
    }
}

/// Asks before disconnecting an account, saying what goes with it, and
/// calls `onDone` only once it is gone (a failed cascade leaves it, its
/// error on its card). Anchored to the control that asks, so iPad's
/// popover points at it. The account page's button and the Mac's "−"
/// both use it.
struct DisconnectConfirmation: ViewModifier {
    let accountID: String
    @Binding var isPresented: Bool
    let onDone: () -> Void
    @Environment(UsageModel.self) private var model

    func body(content: Content) -> some View {
        let name = model.usage(for: accountID)?.account.displayName ?? ""
        content.confirmationDialog(
            Text("Disconnect \(name)?"),
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                if model.disconnect(accountID: accountID) {
                    onDone()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AIMeter forgets its sign-in and deletes its usage history (in iCloud too, if sync is on) and its alerts. Your account with the service isn't touched.")
        }
    }
}

extension View {
    func disconnectConfirmation(accountID: String, isPresented: Binding<Bool>, onDone: @escaping () -> Void) -> some View {
        modifier(DisconnectConfirmation(accountID: accountID, isPresented: isPresented, onDone: onDone))
    }
}

/// The account's settings as a pushed page: from the Settings list's
/// account rows (iOS) and from Provider Detail's "Account settings" row
/// (both platforms, in the Dashboard's navigation stack).
struct AccountSettingsPage: View {
    let accountID: String
    /// Whether disconnecting pops this page. In the Dashboard's stack it
    /// doesn't: the stack goes back to the Dashboard itself once the
    /// account is gone (`ContentView`), since the Provider Detail under
    /// this page has nothing left to show.
    var dismissesOnDisconnect = true

    @Environment(UsageModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            AccountSettingsCards(accountID: accountID, onDisconnect: dismissesOnDisconnect ? { dismiss() } : nil)
                .padding(20)
                .readableWidth()
        }
        .appBackground()
        .navigationTitle(model.usage(for: accountID)?.account.displayName ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// The value the Dashboard's stack pushes for an account's settings page
/// (`DashboardView`'s `navigationDestination`): a value, like Provider
/// Detail's, so the stack's path holds the whole stack and going back to
/// the Dashboard after a disconnect is one reset of it.
struct AccountSettingsRoute: Hashable {
    let accountID: String
}
