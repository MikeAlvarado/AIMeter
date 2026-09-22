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
                        ProviderIdentityView(
                            name: context.attributes.accountName,
                            iconSize: 18,
                            iconCornerRadius: 4,
                            font: .system(size: 13, weight: .semibold),
                            nameColor: Theme.ink,
                            planName: nil
                        )
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
                            tint: UsageWindow.tint(usedPct: context.state.usedPct, severity: context.state.severity)
                        )
                        countdown(context.state, size: 11)
                    }
                }
            } compactLeading: {
                providerMark(size: 16)
            } compactTrailing: {
                HStack(spacing: 4) {
                    percentText(context.state, size: 12)
                    if context.state.isPeak {
                        PeakBadge(size: 9)
                    }
                }
            } minimal: {
                providerMark(size: 14)
            }
        }
    }

    private func providerMark(size: CGFloat) -> some View {
        ProviderMark(size: size, cornerRadius: size / 4)
    }

    private func percentText(_ state: SessionActivityAttributes.ContentState, size: CGFloat) -> some View {
        Text("\(Int(state.usedPct))%")
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
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
                ProviderIdentityView(
                    name: attributes.accountName,
                    iconSize: 20,
                    iconCornerRadius: 4.5,
                    font: .system(size: 14, weight: .semibold),
                    nameColor: Theme.ink,
                    planName: nil
                )
                // Grouped with the account name (leading), not with the
                // percentage (trailing): it's a property of the account,
                // not of the number.
                if state.isPeak {
                    PeakBadge(size: 11)
                }
                Spacer(minLength: 0)
                Text("\(Int(state.usedPct))%")
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            UsageBarView(value: state.usedPct, tint: UsageWindow.tint(usedPct: state.usedPct, severity: state.severity))
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
    }
}
#endif
