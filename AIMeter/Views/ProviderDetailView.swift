import SwiftUI
import UsageKit

/// Claude detail: the same windows in full, plus per-window reset
/// notifications and disconnect. The cards it composes live in
/// `ProviderDetailCards.swift` (Peak, Forecast, raw detail rows) and
/// `NotificationTogglesCards.swift` (both notification cards).
struct ProviderDetailView: View {
    let accountID: String

    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var showingReconnect = false
    @State private var showingRename = false
    @State private var renameDraft = ""

    private var usage: UsageModel.AccountUsage? {
        model.usage(for: accountID)
    }

    /// The nickname, or the provider's name while the account is gone
    /// (the screen is mid-dismiss after a disconnect).
    private var accountName: String {
        usage?.account.displayName ?? ProviderCatalog.displayName(for: ProviderCatalog.defaultProviderID)
    }

    var body: some View {
        @Bindable var prefs = prefs

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: String(localized: "Rate limits"))
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        WindowRowsList(snapshot: usage?.snapshot, accountID: accountID, showsPace: true)
                        UsageStatusFooter(
                            snapshot: usage?.snapshot,
                            error: usage?.lastError,
                            reauthenticate: usage?.needsReauthentication == true ? { showingReconnect = true } : nil,
                            offline: usage?.isOffline == true
                        )
                    }
                }

                // Only while a peak schedule is in force — none is today
                // (the policy is retired, see `ClaudePeakSchedule`).
                if let schedule = ClaudePeakSchedule.current {
                    SectionHeader(title: String(localized: "Peak hours"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    let peakStatus = ClaudePeakStatus(schedule: schedule)
                    PeakHoursCard(status: peakStatus)
                    SectionFootnote(text: "\(peakStatus.scheduleDescription) \(peakStatus.lastVerifiedLabel)")
                }

                if let snapshot = usage?.snapshot, !snapshot.windows.isEmpty {
                    SectionHeader(title: String(localized: "Forecast"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    ForecastCard(snapshot: snapshot, ready: model.paceReady(for: accountID))
                    if model.paceReady(for: accountID) {
                        SectionFootnote(text: String(localized: "Projected from your average pace so far this window. It refines as you use more."))
                    }
                }

                SectionHeader(title: String(localized: "Third usage row"))
                    .padding(.top, Theme.sectionSpacing - 10)
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

                #if os(iOS)
                // macOS's equivalent (which window the menu bar gauge
                // reads) moved to Settings → MacChromeSettings: with
                // several accounts there's no longer one unambiguous
                // account whose Provider Detail could own that control.
                // iOS keeps this here — each Lock Screen widget instance
                // already picks its own account via Edit Widget, and this
                // still decides which of that account's windows the
                // circular gauge reads.
                SectionHeader(title: glanceSectionTitle)
                    .padding(.top, Theme.sectionSpacing - 10)
                Card {
                    SegmentedPill(
                        options: UsageSnapshot.glanceOptions(for: usage?.snapshot, modelSlotFallback: prefs.modelSlotFallback).map { ($0, $0.shortName) },
                        selection: $prefs.glanceMetric
                    )
                }
                SectionFootnote(text: glanceFootnote)

                SectionHeader(title: String(localized: "Live Activity"))
                    .padding(.top, Theme.sectionSpacing - 10)
                Card {
                    Toggle(isOn: liveActivityBinding) {
                        Text("Live Activity")
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.accent)
                }
                SectionFootnote(text: String(localized: "Shows this account's session countdown on the Lock Screen and Dynamic Island while a session is running. Off by default — updates whenever AIMeter or its widgets happen to refresh, not instantly, since there's no server to push updates."))
                #endif

                if let spend = usage?.snapshot?.spend {
                    SectionHeader(title: String(localized: "Spend"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    DetailRowsCard(rows: ProviderDetailRows.spend(spend))
                }

                if let extra = usage?.snapshot?.extraUsage {
                    SectionHeader(title: String(localized: "Extra usage"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    DetailRowsCard(rows: ProviderDetailRows.extraUsage(extra))
                }

                SectionHeader(title: String(localized: "Notifications"))
                    .padding(.top, Theme.sectionSpacing - 10)
                NotificationTogglesCard(accountID: accountID)
                SectionFootnote(text: String(localized: "A local notification fires when the selected usage window resets."))

                SectionHeader(title: String(localized: "Smart notifications"))
                    .padding(.top, Theme.sectionSpacing - 10)
                SmartNotificationTogglesCard(accountID: accountID)
                SectionFootnote(text: SmartNotificationTogglesCard.footnote)

                if !model.isDemoMode {
                    // The discoverable route to the same rename the
                    // Dashboard header's context menu offers — a context
                    // menu announces nothing about itself.
                    SectionHeader(title: String(localized: "Account"))
                        .padding(.top, Theme.sectionSpacing - 10)
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
                    }
                    SectionFootnote(text: String(localized: "Shown on the dashboard, in widgets, and in notification titles."))
                }

                if model.isDemoMode {
                    Button(role: .destructive) {
                        model.exitDemoMode()
                        dismiss()
                    } label: {
                        Text("Exit Demo")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    }
                    .padding(.top, Theme.sectionSpacing - 10)
                } else {
                    Button(role: .destructive) {
                        model.disconnect(accountID: accountID)
                        dismiss()
                    } label: {
                        Text("Disconnect \(accountName)")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    }
                    .padding(.top, Theme.sectionSpacing - 10)
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .sheet(isPresented: $showingReconnect) {
            if let account = usage?.account {
                ConnectClaudeSheet(reconnecting: account)
            }
        }
        .renameAccountAlert(for: accountID, isPresented: $showingRename, name: $renameDraft)
        .navigationTitle(accountName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    #if os(iOS)
    private var glanceSectionTitle: String {
        String(localized: "Lock Screen widget")
    }

    private var glanceFootnote: String {
        String(localized: "Which usage window the Lock Screen circular widget shows. Options match what this account actually reports.")
    }

    /// Reads/writes straight through `LiveActivityPreferences` — no
    /// permission gate needed (unlike notifications), and this is the only
    /// place in the view tree that reads this account's toggle, so a plain
    /// computed `Binding` is enough; no revision-counter invalidation like
    /// the notification toggles need.
    private var liveActivityBinding: Binding<Bool> {
        Binding(
            get: { LiveActivityPreferences(accountID: accountID).enabled },
            set: { newValue in
                LiveActivityPreferences(accountID: accountID).enabled = newValue
                if newValue {
                    LiveActivityManager.sync(
                        accountID: accountID,
                        accountName: accountName,
                        providerID: usage?.account.providerID ?? ProviderCatalog.defaultProviderID,
                        snapshot: usage?.snapshot,
                        enabled: true
                    )
                } else {
                    LiveActivityManager.end(accountID: accountID)
                }
            }
        )
    }
    #endif
}
