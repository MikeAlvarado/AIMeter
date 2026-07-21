import SwiftUI
import UsageKit

/// Claude detail: the same windows in full, plus per-window reset
/// notifications and (iOS) disconnect.
struct ProviderDetailView: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var prefs = prefs

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: String(localized: "Rate limits"))
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        WindowRowsList(snapshot: model.snapshot)
                        if let snapshot = model.snapshot {
                            Divider().overlay(Theme.track)
                            Text(UsageFormatting.updatedLabel(snapshot.fetchedAt))
                                .font(Theme.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }

                SectionHeader(title: String(localized: "Third usage row"))
                    .padding(.top, Theme.sectionSpacing - 10)
                Card {
                    SegmentedPill(
                        options: ModelSlotFallback.allCases.map { ($0, $0.label) },
                        selection: $prefs.modelSlotFallback
                    )
                }
                SectionFootnote(text: String(localized: "Some plans don't include a per-model limit of their own (e.g. Fable 5 on Claude Pro). Auto shows your spend/credits there only when enabled on your account; Hidden and Credits force it off or on."))

                if let spend = model.snapshot?.spend {
                    SectionHeader(title: String(localized: "Spend"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    DetailRowsCard(rows: spendRows(spend))
                }

                if let extra = model.snapshot?.extraUsage {
                    SectionHeader(title: String(localized: "Extra usage"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    DetailRowsCard(rows: extraUsageRows(extra))
                }

                SectionHeader(title: String(localized: "Notifications"))
                    .padding(.top, Theme.sectionSpacing - 10)
                NotificationTogglesCard()
                SectionFootnote(text: String(localized: "A local notification fires when the selected usage window resets."))

                #if os(iOS)
                Button(role: .destructive) {
                    model.disconnect()
                    dismiss()
                } label: {
                    Text("Disconnect Claude")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .padding(.top, Theme.sectionSpacing - 10)
                #endif
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Claude")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func spendRows(_ spend: SpendStatus) -> [(String, String)] {
        var rows = [(String(localized: "Enabled"), yesNo(spend.enabled))]
        if let percent = spend.percent {
            rows.append((String(localized: "Percent"), "\(Int(percent))%"))
        }
        if let severity = spend.severity {
            rows.append((String(localized: "Severity"), severity.rawValue))
        }
        if let used = spend.usedAmount {
            rows.append((String(localized: "Used"), money(used, spend.currency)))
        }
        if let limit = spend.limitAmount {
            rows.append((String(localized: "Limit"), money(limit, spend.currency)))
        }
        return rows
    }

    private func extraUsageRows(_ extra: ExtraUsageStatus) -> [(String, String)] {
        var rows = [(String(localized: "Enabled"), yesNo(extra.enabled))]
        if let used = extra.usedCredits {
            rows.append((String(localized: "Used credits"), money(used, extra.currency)))
        }
        if let limit = extra.monthlyLimit {
            rows.append((String(localized: "Monthly limit"), money(limit, extra.currency)))
        }
        if let utilization = extra.utilization {
            rows.append((String(localized: "Utilization"), "\(Int(utilization))%"))
        }
        return rows
    }

    private func yesNo(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }

    private func money(_ amount: Double, _ currency: String?) -> String {
        amount.formatted(.currency(code: currency ?? "USD"))
    }
}

/// Plain label/value rows with hairline dividers — the raw provider
/// details (Spend, Extra usage) mirroring the reference design.
private struct DetailRowsCard: View {
    let rows: [(String, String)]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider().overlay(Theme.track)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0)
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(row.1)
                            .font(.body)
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }
}

/// Per-window notification toggles over the three fixed slots. When the
/// system permission is denied, a warning row with a settings shortcut
/// replaces the silent no-op.
struct NotificationTogglesCard: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.openURL) private var openURL

    var body: some View {
        Card {
            VStack(spacing: Theme.rowSpacing) {
                let slots = WindowSlots(snapshot: model.snapshot, modelSlotFallback: prefs.modelSlotFallback).slots
                ForEach(Array(slots.enumerated()), id: \.element.kind) { index, slot in
                    if index > 0 {
                        Divider().overlay(Theme.track)
                    }
                    // Credits has no reset date to schedule a notification
                    // against — nothing to toggle, so it stays disabled like
                    // any other slot with no data.
                    let disabled = slot.window == nil || slot.kind == .credits
                    Toggle(isOn: binding(for: slot.kind)) {
                        Text(slot.kind.displayName)
                            .font(Theme.rowTitle)
                            .foregroundStyle(disabled ? Theme.inkSecondary : Theme.ink)
                    }
                    .tint(Theme.accent)
                    .disabled(disabled)
                }
                if model.notificationsBlocked {
                    Divider().overlay(Theme.track)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label(
                            String(localized: "Notifications are off in system Settings."),
                            systemImage: "bell.slash"
                        )
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        Spacer()
                        Button(String(localized: "Open Settings")) {
                            if let url = notificationSettingsURL {
                                openURL(url)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .task {
            await model.refreshNotificationAuthorization()
        }
    }

    private var notificationSettingsURL: URL? {
        #if os(iOS)
        URL(string: UIApplication.openNotificationSettingsURLString)
        #else
        URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        #endif
    }

    private func binding(for kind: UsageWindow.Kind) -> Binding<Bool> {
        Binding(
            get: { model.notificationsEnabled(for: kind) },
            set: { model.setNotificationsEnabled($0, for: kind) }
        )
    }
}
