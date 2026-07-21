import SwiftUI
import WidgetKit
import UsageKit

/// Single-limit widget body: a big percentage for one window the user
/// picked in Edit Widget, its bar, and a reset line — everything else
/// (icon, provider, window label) is secondary and stays small so the
/// number reads at a glance, like the system Battery/Weather widgets.
struct SingleUsageWidgetView: View {
    let entry: SingleUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 4)
            valueBlock
            Spacer(minLength: 10)
            UsageBarView(
                value: entry.window?.displayedPct(entry.prefs.displayMode),
                tint: entry.window?.tint ?? Theme.accent
            )
            resetLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Theme.card
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image("ClaudeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            Text(entry.providerName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 4)
            Text(entry.kind.shortName)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var valueBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let window = entry.window {
                Text("\(Int(window.displayedPct(entry.prefs.displayMode)))%")
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            } else {
                Text("—")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Text(entry.prefs.displayMode.label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
        }
        // One VoiceOver element: "Session, 42%, Used".
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var resetLine: some View {
        if let resetsAt = entry.window?.resetsAt {
            HStack(spacing: 3) {
                Image(systemName: "arrow.circlepath")
                Text(UsageFormatting.resetLabel(for: resetsAt, style: entry.prefs.resetStyle))
            }
            .font(.system(size: 9))
            .foregroundStyle(Theme.inkSecondary.opacity(0.9))
            .padding(.top, 4)
        }
    }
}
