import SwiftUI
import UsageKit

/// Claude detail: the same windows in full, plus per-window reset
/// notifications and disconnect.
struct ProviderDetailView: View {
    let accountID: String

    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.dismiss) private var dismiss

    private var usage: UsageModel.AccountUsage? {
        model.usage(for: accountID)
    }

    var body: some View {
        @Bindable var prefs = prefs

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: String(localized: "Rate limits"))
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        WindowRowsList(snapshot: usage?.snapshot, accountID: accountID, showsPace: true)
                        UsageStatusFooter(snapshot: usage?.snapshot, error: usage?.lastError)
                    }
                }

                SectionHeader(title: String(localized: "Peak hours"))
                    .padding(.top, Theme.sectionSpacing - 10)
                let peakStatus = ClaudePeakStatus()
                PeakHoursCard(status: peakStatus)
                SectionFootnote(text: "\(peakStatus.scheduleDescription) \(peakStatus.lastVerifiedLabel)")

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
                #endif

                if let spend = usage?.snapshot?.spend {
                    SectionHeader(title: String(localized: "Spend"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    DetailRowsCard(rows: spendRows(spend))
                }

                if let extra = usage?.snapshot?.extraUsage {
                    SectionHeader(title: String(localized: "Extra usage"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    DetailRowsCard(rows: extraUsageRows(extra))
                }

                SectionHeader(title: String(localized: "Notifications"))
                    .padding(.top, Theme.sectionSpacing - 10)
                NotificationTogglesCard(accountID: accountID)
                SectionFootnote(text: String(localized: "A local notification fires when the selected usage window resets."))

                SectionHeader(title: String(localized: "Smart notifications"))
                    .padding(.top, Theme.sectionSpacing - 10)
                SmartNotificationTogglesCard(accountID: accountID)
                SectionFootnote(text: SmartNotificationTogglesCard.footnote)

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
                        Text("Disconnect \(usage?.account.displayName ?? "Claude")")
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
        .navigationTitle(usage?.account.displayName ?? "Claude")
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
    #endif

    private func spendRows(_ spend: SpendStatus) -> [(String, String)] {
        var rows = [(String(localized: "Enabled"), yesNo(spend.enabled))]
        if let percent = spend.percent {
            rows.append((String(localized: "Percent"), spend.enabled ? "\(Int(percent))%" : placeholder))
        }
        if let severity = spend.severity {
            rows.append((String(localized: "Severity"), spend.enabled ? severity.rawValue : placeholder))
        }
        if let used = spend.usedAmount {
            rows.append((String(localized: "Used"), spend.enabled ? money(used, spend.currency) : placeholder))
        }
        if let limit = spend.limitAmount {
            rows.append((String(localized: "Limit"), spend.enabled ? money(limit, spend.currency) : placeholder))
        }
        return rows
    }

    private func extraUsageRows(_ extra: ExtraUsageStatus) -> [(String, String)] {
        var rows = [(String(localized: "Enabled"), yesNo(extra.enabled))]
        if let used = extra.usedCredits {
            rows.append((String(localized: "Used credits"), extra.enabled ? money(used, extra.currency) : placeholder))
        }
        if let limit = extra.monthlyLimit {
            rows.append((String(localized: "Monthly limit"), extra.enabled ? money(limit, extra.currency) : placeholder))
        }
        if let utilization = extra.utilization {
            rows.append((String(localized: "Utilization"), extra.enabled ? "\(Int(utilization))%" : placeholder))
        }
        return rows
    }

    private func yesNo(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }

    /// Shown instead of a figure when the account has this feature off —
    /// the endpoint still reports stale percent/used/limit values even
    /// then, and this is the same "no live data" placeholder every other
    /// row in the app uses instead of a misleading number.
    private var placeholder: String { "—" }

    private func money(_ amount: Double, _ currency: String?) -> String {
        amount.formatted(.currency(code: currency ?? "USD"))
    }
}

/// Anthropic's documented weekday peak-usage window, computed on-device
/// from a fixed schedule (see `ClaudePeakSchedule`) — there's no server
/// signal to key off instead (`docs/design/peak-hours-investigation.md`).
private struct PeakHoursCard: View {
    let status: ClaudePeakStatus

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: status.isPeak ? "bolt.fill" : "bolt.slash")
                    .foregroundStyle(status.isPeak ? Theme.danger : Theme.inkSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title)
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Text(status.subtitle)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Per-window run-out forecast from the average pace so far — a warning
/// row for each window projected to hit its limit before it resets, or a
/// single reassuring row when none are. Uses the stable average-rate
/// projection (works from a single snapshot); the recent-rate refinement
/// is what drives the alerts, not this display.
private struct ForecastCard: View {
    let snapshot: UsageSnapshot
    /// While false (pace still warming up), the card shows a "learning"
    /// state rather than a forecast — see `UsageModel.paceReady`.
    var ready = true

    var body: some View {
        if ready {
            forecast
        } else {
            learning
        }
    }

    private var learning: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "hourglass")
                    .foregroundStyle(Theme.inkSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Learning your pace…")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Text("Insights appear after a couple of sessions to learn from.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var forecast: some View {
        // Gate on the Phase-1 pace status so the forecast and the row's
        // "Ahead of pace" caption never disagree — a window only "runs out
        // early" here when it's genuinely ahead (beyond the pace tolerance),
        // not by a trivial fraction.
        let atRisk: [(UsageWindow.Kind, RunOutProjection)] = snapshot.windows.compactMap { window in
            guard PaceCalculator.pace(for: window)?.status == .ahead,
                  let projection = RunOutPredictor.averageProjection(for: window),
                  projection.runsOutEarly else { return nil }
            return (window.kind, projection)
        }

        return Card {
            if atRisk.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.accent)
                    Text("Every limit is on track to last its window.")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                    ForEach(Array(atRisk.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Divider().overlay(Theme.track)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.0.displayName)
                                .font(Theme.rowTitle)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(runsOutText(item.1))
                                .font(.body)
                                .foregroundStyle(Theme.danger)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }

    private func runsOutText(_ projection: RunOutProjection) -> String {
        let early = UsageFormatting.relativeString(from: projection.projectedExhaustion, to: projection.resetsAt)
        return String(localized: "Runs out ~\(early) early")
    }
}

/// This account's "smart" notification toggles: near-limit, limit-reached,
/// run-out, and early-reset — all gate permission through `UsageModel` and
/// fire on detection at fetch time (near-limit / limit-reached /
/// early-reset) or are scheduled ahead (run-out). Peak-hours alerts are a
/// separate toggle in Settings, not here — it's one Claude-wide policy
/// (`UsageModel.peakPreferences`) shared by every account, not tied to
/// this one. Near-limit reveals a threshold slider when on.
struct SmartNotificationTogglesCard: View {
    let accountID: String
    @Environment(UsageModel.self) private var model

    /// Shared caption for the section.
    static var footnote: String {
        String(localized: "Near-limit warns you at the level you set. Limit reached fires when a window maxes out — and whether continuing uses credits. Run-out warnings predict an early exhaustion. Early-reset alerts fire when a limit refills ahead of schedule.")
    }

    var body: some View {
        Card {
            VStack(spacing: Theme.rowSpacing) {
                toggle(String(localized: "Near-limit warnings"),
                       isOn: model.nearLimitEnabled(for: accountID),
                       set: { model.setNearLimitEnabled($0, accountID: accountID) })
                if model.nearLimitEnabled(for: accountID) {
                    thresholdRow
                }

                divider
                toggle(String(localized: "Limit reached"),
                       isOn: model.limitReachedEnabled(for: accountID),
                       set: { model.setLimitReachedEnabled($0, accountID: accountID) })

                divider
                toggle(String(localized: "Run-out warnings"),
                       isOn: model.runOutWarningsEnabled(for: accountID),
                       set: { model.setRunOutWarningsEnabled($0, accountID: accountID) })

                divider
                toggle(String(localized: "Early-reset alerts"),
                       isOn: model.earlyResetAlertsEnabled(for: accountID),
                       set: { model.setEarlyResetAlertsEnabled($0, accountID: accountID) })
            }
        }
        .task {
            await model.refreshNotificationAuthorization()
        }
    }

    private var divider: some View { Divider().overlay(Theme.track) }

    private func toggle(_ title: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: set)) {
            Text(title)
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.ink)
        }
        .tint(Theme.accent)
    }

    private var thresholdRow: some View {
        HStack(spacing: 10) {
            Text("Warn at")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
            Slider(
                value: Binding(
                    get: { model.nearLimitThreshold(for: accountID) },
                    set: { model.setNearLimitThreshold($0, accountID: accountID) }
                ),
                in: 50...95,
                step: 5
            )
            .tint(Theme.accent)
            Text("\(Int(model.nearLimitThreshold(for: accountID)))%")
                .font(Theme.caption.monospacedDigit())
                .foregroundStyle(Theme.ink)
                .frame(width: 42, alignment: .trailing)
        }
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

/// Per-window notification toggles over the three fixed slots, for one
/// account. When the system permission is denied, a warning row with a
/// settings shortcut replaces the silent no-op.
struct NotificationTogglesCard: View {
    let accountID: String
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.openURL) private var openURL

    private var snapshot: UsageSnapshot? {
        model.usage(for: accountID)?.snapshot
    }

    var body: some View {
        Card {
            VStack(spacing: Theme.rowSpacing) {
                let slots = WindowSlots(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback).slots
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
            get: { model.notificationsEnabled(for: kind, accountID: accountID) },
            set: { model.setNotificationsEnabled($0, for: kind, accountID: accountID) }
        )
    }
}
