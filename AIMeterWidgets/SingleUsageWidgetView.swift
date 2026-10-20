import SwiftUI
import WidgetKit
import UsageKit

/// Single-limit widget body: a big percentage for one window the user
/// picked in Edit Widget, its bar, and a reset line — everything else
/// (icon, provider, window label) is secondary and stays small so the
/// number reads at a glance, like the system Battery/Weather widgets.
/// Or, with the ring style picked there too, the figure in a ring
/// (`RingUsageView`).
struct SingleUsageWidgetView: View {
    let entry: SingleUsageEntry

    var body: some View {
        Group {
            if entry.style == .ring {
                RingUsageView(entry: entry)
            } else {
                bars
            }
        }
        .containerBackground(for: .widget) {
            Theme.card
        }
    }

    private var bars: some View {
        VStack(alignment: .leading, spacing: 0) {
            SingleUsageHeader(entry: entry, trailing: entry.windowName)
            Spacer(minLength: 4)
            valueBlock
            Spacer(minLength: 10)
            UsageBarView(
                value: entry.window?.displayedPct(entry.prefs.displayMode),
                tint: entry.window?.tint(usageColors: entry.prefs.usageColors) ?? Theme.accent
            )
            resetLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var valueBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let window = entry.window {
                Text("\(Int(window.displayedPct(entry.prefs.displayMode)))%")
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            } else {
                Text("--")
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
                ResetLineText(resetsAt: resetsAt, style: entry.prefs.resetStyle, now: entry.date)
            }
            .font(.system(size: 9))
            .foregroundStyle(Theme.inkSecondary.opacity(0.9))
            .padding(.top, 4)
        } else if let amount = entry.prefs.creditsAmountSubtitle(for: entry.kind, snapshot: entry.snapshot) {
            HStack(spacing: 3) {
                Image(systemName: "dollarsign.circle")
                Text(amount)
            }
            .font(.system(size: 9))
            .foregroundStyle(Theme.inkSecondary.opacity(0.9))
            .lineLimit(1)
            .padding(.top, 4)
        }
    }
}

extension SingleUsageEntry {
    /// The picked window's compact name with its real length, else the
    /// kind's own while the account has no window of it.
    var windowName: String { window?.shortTitle ?? kind.shortName }
}

/// The account's name with its mark, and on the trailing edge the window
/// (bar style) or the display mode (ring style, whose centre names the
/// window), with the peak badge between for a session in peak hours.
private struct SingleUsageHeader: View {
    let entry: SingleUsageEntry
    let trailing: String

    var body: some View {
        HStack(spacing: 5) {
            ProviderIdentityView(
                name: entry.accountName,
                iconSize: 15,
                iconCornerRadius: 3.5,
                font: .system(size: 12, weight: .semibold),
                nameColor: Theme.ink,
                planName: nil,
                icon: entry.accountIcon
            )
            Spacer(minLength: 4)
            // Scoped to .session: that's the window the documented peak
            // policy actually affects, so a Weekly/Credits/model pick
            // never shows a badge that would misattribute it.
            if entry.kind == .session, ClaudePeakStatus.forProvider(entry.snapshot?.providerID, at: entry.date).isPeak {
                PeakBadge(size: 9)
            }
            Text(trailing)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
        }
    }
}

/// The ring style: the header, then the window as a ring in its level's
/// color, the figure in the centre over the window's name and its reset,
/// a live countdown under a day ("Session · 2:23:05", `ResetLineText`'s
/// bare form). The track is the bars' and the stroke the same 9 pt the
/// mockup it was picked from had; the display mode moves up to the
/// header, where the bar style names the window.
private struct RingUsageView: View {
    let entry: SingleUsageEntry
    private static let strokeWidth: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SingleUsageHeader(entry: entry, trailing: entry.prefs.displayMode.label)
            Spacer(minLength: 2)
            ZStack {
                Circle()
                    .stroke(Theme.track, lineWidth: Self.strokeWidth)
                if let window = entry.window {
                    Circle()
                        .trim(from: 0, to: min(max(window.displayedPct(entry.prefs.displayMode), 0), 100) / 100)
                        .stroke(
                            window.tint(usageColors: entry.prefs.usageColors),
                            style: StrokeStyle(lineWidth: Self.strokeWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 1) {
                    Text(entry.window.map { "\(Int($0.displayedPct(entry.prefs.displayMode)))%" } ?? "--")
                        .font(.system(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(entry.window == nil ? Theme.inkSecondary : Theme.ink)
                    caption
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, Self.strokeWidth + 6)
            }
            // The stroke straddles the circle's edge: half of it lies
            // outside the frame without this.
            .padding(Self.strokeWidth / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // One VoiceOver element: "42%, Session, 2:23:05".
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var caption: some View {
        if let resetsAt = entry.window?.resetsAt {
            HStack(spacing: 3) {
                Text(entry.windowName)
                Text(verbatim: "·")
                ResetLineText(resetsAt: resetsAt, style: entry.prefs.resetStyle, now: entry.date, bare: true)
            }
        } else if let amount = entry.prefs.creditsAmountSubtitle(for: entry.kind, snapshot: entry.snapshot) {
            Text(verbatim: "\(entry.windowName) · \(amount)")
        } else {
            Text(entry.windowName)
        }
    }
}
