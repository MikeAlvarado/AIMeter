import SwiftUI
import UsageKit

/// This account's "smart" notification toggles — one per `SmartAlert`,
/// all gating permission through `UsageModel` and firing on detection at
/// fetch time (near-limit / limit-reached / early-reset / sign-in) or
/// scheduled ahead (run-out). Peak-hours alerts are a separate toggle in
/// Settings, not here — it's one Claude-wide policy
/// (`UsageModel.peakPreferences`) shared by every account, not tied to
/// this one. Near-limit reveals its levels when on: up to three sliders.
struct SmartNotificationTogglesCard: View {
    let accountID: String
    @Environment(UsageModel.self) private var model

    var body: some View {
        Card {
            VStack(spacing: Theme.rowSpacing) {
                ForEach(Array(SmartAlert.allCases.enumerated()), id: \.element) { index, alert in
                    if index > 0 {
                        Divider().overlay(Theme.track)
                    }
                    let enabled = model.smartAlertEnabled(alert, for: accountID)
                    Toggle(isOn: Binding(
                        get: { enabled },
                        set: { model.setSmartAlertEnabled($0, alert, accountID: accountID) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title)
                                .font(Theme.rowTitle)
                                .foregroundStyle(Theme.ink)
                            Text(alert.detail)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Theme.accent)
                    if alert == .nearLimit, enabled {
                        thresholdRows
                    }
                }
            }
        }
        .task {
            await model.refreshNotificationAuthorization()
        }
    }

    /// One slider per level, a minus beside each while there are two or
    /// more, and "Add a level" while there are fewer than three. The
    /// levels keep the order they were set in, so a row never jumps while
    /// its slider is dragged.
    private var thresholdRows: some View {
        let levels = model.nearLimitThresholds(for: accountID)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                HStack(spacing: 10) {
                    Text("Warn at")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    Slider(
                        value: Binding(
                            get: { level },
                            set: { newValue in
                                var updated = levels
                                updated[index] = newValue
                                model.setNearLimitThresholds(updated, accountID: accountID)
                            }
                        ),
                        in: 50...95,
                        step: 5
                    )
                    .tint(Theme.accent)
                    // Its own name and the percent it warns at: as a bare slider
                    // VoiceOver read 50 % as "0 percent" (the start of 50...95).
                    .accessibilityLabel(Text("Warn at"))
                    .accessibilityValue(Text(verbatim: "\(Int(level))%"))
                    Text("\(Int(level))%")
                        .font(Theme.caption.monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .frame(width: 42, alignment: .trailing)
                    if levels.count > 1 {
                        Button {
                            var updated = levels
                            updated.remove(at: index)
                            model.setNearLimitThresholds(updated, accountID: accountID)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Theme.inkSecondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove \(Int(level))%"))
                    }
                }
            }
            if levels.count < NotificationPreferences.maxNearLimitThresholds {
                Button {
                    let next = min(95, (levels.max() ?? 75) + 10)
                    model.setNearLimitThresholds(levels + [next], accountID: accountID)
                } label: {
                    Label("Add a level", systemImage: "plus.circle")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tapTarget()
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
                        Text(slot.window?.title ?? slot.kind.displayName)
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
