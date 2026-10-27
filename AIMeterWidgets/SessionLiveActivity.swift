#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit
import UsageKit

/// Session-window countdown on the Lock Screen and Dynamic Island. See
/// "Live Activity" in this target's CLAUDE.md for the full design — one
/// activity per opted-in account, updated opportunistically by whichever
/// fetch (app or widget self-fetch) happens to run next, never pushed.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Theme.card)
                .activitySystemActionForegroundColor(Theme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        if let pet = context.attributes.sessionPet {
                            HStack(spacing: 6) {
                                ActivityPetView(pet: pet, mood: SessionPetMood(context.state), height: 30)
                                accountName(context.attributes.accountName, size: 13)
                            }
                        } else {
                            ProviderIdentityView(
                                name: context.attributes.accountName,
                                iconSize: 18,
                                iconCornerRadius: 4,
                                font: .system(size: 13, weight: .semibold),
                                nameColor: Theme.ink,
                                planName: nil,
                                icon: context.attributes.accountIcon
                            )
                        }
                        if context.state.isPeak {
                            PeakBadge(size: 10)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    percentText(context.state, size: 15)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        UsageBarView(
                            value: context.state.usedPct,
                            tint: UsageWindow.tint(usedPct: context.state.usedPct, severity: context.state.severity, usageColors: Preferences.load().usageColors)
                        )
                        countdown(context.state, size: 11)
                    }
                }
            } compactLeading: {
                if let pet = context.attributes.sessionPet {
                    ActivityPetView(pet: pet, mood: SessionPetMood(context.state), height: 24)
                } else {
                    providerMark(size: 16, icon: context.attributes.accountIcon)
                }
            } compactTrailing: {
                HStack(spacing: 4) {
                    percentText(context.state, size: 12)
                    if context.state.isPeak {
                        PeakBadge(size: 9)
                    }
                }
            } minimal: {
                if let pet = context.attributes.sessionPet {
                    ActivityPetView(pet: pet, mood: SessionPetMood(context.state), height: 20, showsMark: false)
                } else {
                    providerMark(size: 14, icon: context.attributes.accountIcon)
                }
            }
        }
    }

    private func providerMark(size: CGFloat, icon: AccountIcon?) -> some View {
        ProviderMark(size: size, cornerRadius: size / 4, icon: icon)
    }

    /// The name beside the pet, styled as `ProviderIdentityView` styles it
    /// beside the icon.
    private func accountName(_ name: String, size: CGFloat) -> some View {
        Text(name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func percentText(_ state: SessionActivityAttributes.ContentState, size: CGFloat) -> some View {
        Text("\(Int(state.usedPct))%")
            .font(Theme.figure(size: size))
            .foregroundStyle(Theme.ink)
    }

    private func countdown(_ state: SessionActivityAttributes.ContentState, size: CGFloat) -> some View {
        let end = max(state.resetsAt, Date().addingTimeInterval(1))
        return HStack(spacing: 3) {
            Image(systemName: "arrow.circlepath")
            Text(timerInterval: Date()...end, countsDown: true)
        }
        .font(.system(size: size))
        .foregroundStyle(Theme.inkSecondary)
    }
}

private struct LockScreenView: View {
    let attributes: SessionActivityAttributes
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let pet = attributes.sessionPet {
                    ActivityPetView(pet: pet, mood: SessionPetMood(state), height: 24, onIsland: false)
                    Text(attributes.accountName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    ProviderIdentityView(
                        name: attributes.accountName,
                        iconSize: 20,
                        iconCornerRadius: 4.5,
                        font: .system(size: 14, weight: .semibold),
                        nameColor: Theme.ink,
                        planName: nil,
                        icon: attributes.accountIcon
                    )
                }
                // Grouped with the account name (leading), not with the
                // percentage (trailing): it's a property of the account,
                // not of the number.
                if state.isPeak {
                    PeakBadge(size: 11)
                }
                Spacer(minLength: 0)
                Text("\(Int(state.usedPct))%")
                    .font(Theme.figure(size: 16))
                    .foregroundStyle(Theme.ink)
            }
            UsageBarView(value: state.usedPct, tint: UsageWindow.tint(usedPct: state.usedPct, severity: state.severity, usageColors: Preferences.load().usageColors))
                .frame(height: Theme.barHeight)
            HStack(spacing: 4) {
                Image(systemName: "arrow.circlepath")
                Text(timerInterval: Date()...max(state.resetsAt, Date().addingTimeInterval(1)), countsDown: true)
                Text("until reset")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkSecondary)
        }
        .padding(16)
        // One VoiceOver element: the account, its figure and the countdown.
        .accessibilityElement(children: .combine)
    }
}
#endif
