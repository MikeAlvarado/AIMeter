import SwiftUI
import UsageKit

/// Settings' accounts card: one row per account (its mark, name and plan,
/// the service under it, or "Sign in again" when its login stopped
/// working), each opening its own settings (`AccountSettingsCards`), then
/// "Add account" and, with two or more, "Order by urgency". On iOS a row
/// pushes the account's page and "Add account" opens the Connect sheet
/// over Settings; the Mac's Accounts tab is a list and a detail pane
/// instead (`MacAccountsSettingsPage`), which draws the same rows.
struct AccountListSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @State private var connecting = false

    var body: some View {
        SectionHeader(title: String(localized: "Accounts"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                ForEach(model.accounts) { usage in
                    if usage.id != model.accounts.first?.id {
                        Divider().overlay(Theme.track)
                    }
                    NavigationLink {
                        AccountSettingsPage(accountID: usage.id)
                    } label: {
                        AccountListRow(usage: usage, chevron: true)
                    }
                    .buttonStyle(.plain)
                }
                if model.accounts.isEmpty {
                    Text("No account connected.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                // In demo mode a connection would land under the fabricated
                // accounts (the Dashboard's "Add account" hides there too).
                if !model.isDemoMode {
                    Divider().overlay(Theme.track)
                    Button {
                        connecting = true
                    } label: {
                        Label("Add account", systemImage: "plus")
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if AccountOrderToggle.isOffered(model) {
                    Divider().overlay(Theme.track)
                    AccountOrderToggle()
                }
            }
        }
        .sheet(isPresented: $connecting) {
            ConnectAccountSheet()
                .withAppModels(model, prefs)
        }
        SectionFootnote(text: AccountOrderToggle.isOffered(model)
            ? String(localized: "Each account's notifications, Live Activity, name and icon, and disconnecting it.") + " " + AccountOrderToggle.footnote
            : String(localized: "Each account's notifications, Live Activity, name and icon, and disconnecting it."))
    }
}

/// One account in Settings: its mark, its name with the plan beside it,
/// and under them the service it belongs to, or "Sign in again" in red
/// while its login doesn't work. The row's control (a link, a button, the
/// Mac list's selection) reads as one element to VoiceOver.
struct AccountListRow: View {
    let usage: UsageModel.AccountUsage
    var chevron = false

    var body: some View {
        HStack(spacing: 10) {
            ProviderMark(size: 28, cornerRadius: 7, icon: usage.account.icon)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: usage.account.displayName)
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let plan = usage.snapshot?.planName {
                        PlanPill(name: plan, compact: true)
                    }
                }
                if usage.needsReauthentication {
                    Text("Sign in again")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                } else {
                    Text(verbatim: ProviderCatalog.displayName(for: usage.account.providerID))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// "Usage rows": the third row's fallback and the credits amount, one
/// shared value for every account (see "Display prefs" in the repo-root
/// CLAUDE.md), so they are general settings and live here rather than on
/// an account's page.
struct UsageRowsSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    /// The third row's fallback reaches every account with a session or a
    /// week, Claude's and Codex's (Codex reports spend too), never one of
    /// Copilot's quotas: the section shows unless every account is
    /// Copilot's (and with none yet, or in the demo).
    static func applies(toFamilies providerIDs: [String], demo: Bool) -> Bool {
        demo || providerIDs.isEmpty || providerIDs.contains { $0 != CopilotProvider.providerID }
    }

    static func isOffered(_ model: UsageModel) -> Bool {
        applies(toFamilies: model.accounts.map(\.account.providerID), demo: model.isDemoMode)
    }

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Usage rows"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                SegmentedPill(
                    options: ModelSlotFallback.allCases.map { ($0, $0.label) },
                    selection: $prefs.modelSlotFallback
                )
                Divider().overlay(Theme.track)
                Toggle(isOn: $prefs.showCreditsAmount) {
                    Text("Show credit amounts")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)
            }
        }
        // The Claude example only to someone with a Claude account.
        if model.isDemoMode || ProviderCatalog.familiesToDescribe(connected: model.accounts.map(\.account.providerID)).contains(ClaudeProvider.providerID) {
            SectionFootnote(text: String(localized: "Some plans don't include a per-model limit of their own (e.g. Fable 5 on Claude Pro). Auto shows your spend/credits there only when enabled on your account; Hidden and Credits force it off or on. When the Credits row shows, \"Show credit amounts\" adds its $ used and limit under the row in place of a reset line."))
        } else {
            SectionFootnote(text: String(localized: "Some plans don't include a per-model limit of their own. Auto shows your spend/credits there only when enabled on your account; Hidden and Credits force it off or on. When the Credits row shows, \"Show credit amounts\" adds its $ used and limit under the row in place of a reset line."))
        }
    }
}

#if os(iOS)
/// "Lock Screen widget": which window the circular gauge reads, for
/// whichever account a widget instance is set to (`glanceMetric`, one
/// shared value; see "Display prefs" in the repo-root CLAUDE.md). The
/// options are the union of what the accounts report.
struct GlanceMetricSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    private var options: [UsageWindow.Kind] {
        var seen: [UsageWindow.Kind] = []
        let snapshots: [UsageSnapshot?] = model.accounts.isEmpty ? [nil] : model.accounts.map(\.snapshot)
        for snapshot in snapshots {
            for kind in UsageSnapshot.glanceOptions(for: snapshot, modelSlotFallback: prefs.modelSlotFallback) where !seen.contains(kind) {
                seen.append(kind)
            }
        }
        return seen
    }

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Lock Screen widget"))
        Card {
            SegmentedPill(options: options.map { ($0, $0.shortName) }, selection: $prefs.glanceMetric)
        }
        SectionFootnote(text: String(localized: "Which usage window the Lock Screen circular widget shows, whichever account it is set to. The options are what your accounts report."))
    }
}
#endif
