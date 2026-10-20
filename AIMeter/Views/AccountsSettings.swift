import SwiftUI
import UsageKit

/// Settings' account list (iOS): one row per account, each opening its
/// own page (`AccountSettingsPage`). The general sections around it never
/// repeat what a page holds.
struct AccountListSettings: View {
    @Environment(UsageModel.self) private var model

    static func isOffered(_ model: UsageModel) -> Bool {
        !model.accounts.isEmpty
    }

    var body: some View {
        SectionHeader(title: String(localized: "Account settings"))
        Card {
            ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, usage in
                if index > 0 {
                    Divider().overlay(Theme.track)
                }
                NavigationLink {
                    AccountSettingsPage(accountID: usage.id)
                } label: {
                    HStack(spacing: 10) {
                        ProviderIdentityView(
                            name: usage.account.displayName,
                            iconSize: 24,
                            iconCornerRadius: 6,
                            font: Theme.rowTitle,
                            nameColor: Theme.ink,
                            planName: usage.snapshot?.planName,
                            icon: usage.account.icon
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        SectionFootnote(text: String(localized: "Each account's notifications, Live Activity, name and icon."))
    }
}

/// "Usage rows": the third row's fallback and the credits amount, one
/// shared value for every account (see "Display prefs" in the repo-root
/// CLAUDE.md), so they are general settings and live here rather than on
/// an account's page.
struct UsageRowsSettings: View {
    @Environment(PreferencesModel.self) private var prefs

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
        SectionFootnote(text: String(localized: "Some plans don't include a per-model limit of their own (e.g. Fable 5 on Claude Pro). Auto shows your spend/credits there only when enabled on your account; Hidden and Credits force it off or on. When the Credits row shows, \"Show credit amounts\" adds its $ used and limit under the row in place of a reset line."))
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

#if os(macOS)
/// The Mac Settings window's Accounts tab: what concerns the accounts as
/// a whole (their order, discreet mode, the main one), then one account's
/// own settings under a picker, the same cards the account's page shows.
struct MacAccountsSettingsPage: View {
    @Environment(UsageModel.self) private var model
    @State private var pickedID: String?

    /// The picked account while it is still connected, else the first.
    private var selectedID: String? {
        if let pickedID, model.accounts.contains(where: { $0.id == pickedID }) { return pickedID }
        return model.accounts.first?.id
    }

    var body: some View {
        if AccountOrderSettings.isOffered(model) {
            AccountOrderSettings()
            SettingsGap()
        }
        if DiscreetModeSettings.isOffered(model) {
            DiscreetModeSettings()
            SettingsGap()
        }
        if model.accounts.count > 1 {
            SectionHeader(title: String(localized: "Main account"))
            Card {
                PrimaryAccountPicker()
            }
            SettingsGap()
        }
        SectionHeader(title: String(localized: "Account settings"))
        if let selectedID {
            if model.accounts.count > 1 {
                Card {
                    HStack {
                        Text("Account")
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Picker("Account", selection: Binding(get: { selectedID }, set: { pickedID = $0 })) {
                            ForEach(model.accounts) { usage in
                                Text(usage.account.displayName).tag(usage.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .tint(Theme.accent)
                    }
                }
            }
            AccountSettingsCards(accountID: selectedID, onDisconnect: { pickedID = nil })
        } else {
            SectionFootnote(text: String(localized: "No account connected."))
        }
    }
}
#endif
