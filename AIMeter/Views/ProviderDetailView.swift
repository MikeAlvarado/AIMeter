import SwiftUI
import UsageKit

/// Claude detail: what the account shows — the same windows in full,
/// its history, forecast, spend and extra usage — and, in its toolbar,
/// the way to its own settings (`AccountSettingsPage`: notifications,
/// name and icon, disconnecting), which live there and nowhere else. The
/// cards it composes live in `ProviderDetailCards.swift` (Peak,
/// Forecast, raw detail rows).
struct ProviderDetailView: View {
    let accountID: String

    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @State private var showingReconnect = false

    private var usage: UsageModel.AccountUsage? {
        model.usage(for: accountID)
    }

    /// The nickname, or nothing while the account is gone (the stack is
    /// on its way back to the Dashboard after a disconnect): a provider's
    /// name there read as another account's screen.
    private var accountName: String {
        usage?.account.displayName ?? ""
    }

    var body: some View {
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
                            offline: usage?.isOffline == true,
                            serviceIncident: usage.flatMap(model.incidentNote(for:))
                        )
                    }
                }
                if let usage, let note = model.serviceStatusFootnote(for: usage.account.providerID) {
                    SectionFootnote(text: note)
                }

                if let snapshot = usage?.snapshot, !snapshot.windows.isEmpty {
                    SectionHeader(title: String(localized: "History"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    HistoryCard(accountID: accountID, snapshot: snapshot)
                    SectionFootnote(text: String(localized: "Percent of the limit used, sampled whenever AIMeter or a widget refreshes and kept on this device for 30 days. Dashed lines mark resets; the red line is the 85% mark."))
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
            }
            .padding(20)
            .readableWidth()
        }
        .appBackground()
        .sheet(isPresented: $showingReconnect) {
            if let account = usage?.account {
                ConnectAccountSheet(reconnecting: account)
                    .withAppModels(model, prefs)
            }
        }
        .navigationTitle(accountName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // The account's own settings, a tap away from its card (Mike,
        // 2026-10-22: a row at the end of the page went unfound).
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: AccountSettingsRoute(accountID: accountID)) {
                    Label("Account settings", systemImage: "slider.horizontal.3")
                }
                .help(Text("Account settings"))
            }
        }
    }
}
