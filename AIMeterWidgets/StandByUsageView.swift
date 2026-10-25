#if os(iOS)
import SwiftUI
import UsageKit
import WidgetKit

/// A small widget in StandBy (the iPhone charging on its side), where the
/// system takes the widget's background away and shows it large across
/// the room: one window, read from a distance. The account's name small,
/// the figure as large as the square allows, the window and its reset,
/// and its bar; no header, no refresh button, nothing to read up close.
/// At night the system tints it red by itself. Also what an iPad's Lock
/// Screen shows, the other place a widget loses its background.
struct StandByUsageView: View {
    let accountName: String
    let windowName: String
    let window: UsageWindow?
    let prefs: Preferences
    let now: Date
    var moneySubtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(accountName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if let window {
                    Text(verbatim: "\(Int(window.displayedPct(prefs.displayMode)))")
                        .font(Theme.figure(size: 66))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: "%")
                        .font(Theme.figure(size: 26))
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    Text(verbatim: "--")
                        .font(Theme.figure(size: 66))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                Text(windowName)
                    .foregroundStyle(Theme.ink)
                if let resetsAt = window?.resetsAt {
                    Image(systemName: "arrow.circlepath")
                        .foregroundStyle(Theme.inkSecondary)
                    ResetLineText(resetsAt: resetsAt, style: prefs.resetStyle, now: now, bare: true)
                        .foregroundStyle(Theme.inkSecondary)
                } else if let moneySubtitle {
                    Text(moneySubtitle)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.bottom, 8)
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                height: 6
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
#endif
