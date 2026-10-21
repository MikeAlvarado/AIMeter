import SwiftUI
import WidgetKit
import UsageKit
#if os(iOS)
import AppIntents
#endif

/// System families show the account header plus capsule bars with reset
/// times: the small family as stacked rows mirroring the dashboard, the
/// medium as side-by-side columns with a big figure each. All views honor
/// the Remaining/Used and Relative/Absolute preferences from the App Group.
struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                #if os(iOS)
                case .accessoryCircular:
                    CircularUsageView(snapshot: snapshot, prefs: entry.prefs)
                case .accessoryRectangular:
                    RectangularUsageView(snapshot: snapshot, prefs: entry.prefs)
                case .accessoryInline:
                    InlineUsageView(snapshot: snapshot, prefs: entry.prefs)
                #endif
                case .systemMedium:
                    MediumUsageView(snapshot: snapshot, prefs: entry.prefs, date: entry.date, accountID: entry.accountID, accountName: entry.accountName, accountIcon: entry.accountIcon)
                default:
                    SystemUsageView(snapshot: snapshot, prefs: entry.prefs, date: entry.date, accountID: entry.accountID, accountName: entry.accountName, accountIcon: entry.accountIcon)
                }
            } else {
                Text("Open AIMeter to load usage")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .containerBackground(for: .widget) {
            Theme.card
        }
    }
}

// MARK: - System families

/// Account name with the mark; shows a staleness hint on the trailing
/// edge so it never costs an extra row. Widget fonts are fixed sizes on
/// purpose: text styles scale with the device's Dynamic Type and overflow
/// the fixed widget height on real hardware. Internal: `MediumUsageView`
/// (its own file) uses the same header over its columns.
struct WidgetHeader: View {
    let snapshot: UsageSnapshot
    /// The rendered timeline entry's own date — not `Date()` — so the
    /// peak badge matches whichever entry WidgetKit is currently
    /// displaying, including a future entry dated at the next peak
    /// transition (see `UsageTimelineProvider.peakTransitionEntry`).
    let date: Date
    let accountID: String
    let accountName: String
    /// The plan pill; the small family leaves it out for room.
    var planName: String? = nil
    var accountIcon: AccountIcon? = nil

    var body: some View {
        HStack(spacing: 5) {
            ProviderIdentityView(
                name: accountName,
                iconSize: 15,
                iconCornerRadius: 3.5,
                font: .system(size: 12, weight: .semibold),
                nameColor: Theme.ink,
                planName: planName,
                icon: accountIcon
            )
            Spacer(minLength: 0)
            if ClaudePeakStatus.forProvider(snapshot.providerID, at: date).isPeak {
                PeakBadge(size: 9)
            }
            if snapshot.isStale {
                HStack(spacing: 2) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(snapshot.fetchedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                }
                .font(.system(size: 8))
                .foregroundStyle(Theme.inkSecondary.opacity(0.8))
            }
            #if os(iOS)
            // Always present, not just while stale — a predictable, always-
            // available manual refresh, same philosophy as the app's own
            // Dashboard refresh button. macOS omits it: a sandboxed widget
            // there has no credentials to fetch with (see `WidgetRefresher`).
            Button(intent: RefreshAccountIntent(accountID: accountID)) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .buttonStyle(.plain)
            #endif
        }
    }
}

/// Small: the app's account card in a small square (4.0) — the header,
/// the most urgent window as the protagonist (its name, the figure large,
/// a thicker bar, and the reset beside the figure as a bare live
/// countdown), then up to two other windows as compact lines (name, a thin
/// bar, the figure). The same `AccountCardLayout` decides which leads, so
/// the widget and the Dashboard always agree. The medium family is
/// `MediumUsageView`, columns, like the Mac's popover.
struct SystemUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences
    let date: Date
    let accountID: String
    let accountName: String
    var accountIcon: AccountIcon? = nil

    var body: some View {
        let layout = AccountCardLayout(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback)
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(snapshot: snapshot, date: date, accountID: accountID, accountName: accountName, accountIcon: accountIcon)
            Spacer(minLength: 8)
            WidgetHero(
                kind: layout.hero.kind,
                window: layout.hero.window,
                prefs: prefs,
                now: date,
                moneySubtitle: prefs.creditsAmountSubtitle(for: layout.hero.kind, snapshot: snapshot),
                figureSize: 28
            )
            Spacer(minLength: 8)
            WidgetCompactRows(slots: Array(layout.others.prefix(2)), prefs: prefs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A widget's protagonist (the small family, and each account of the
/// all-accounts widget): the window's name, the figure with its reset on
/// the same line, and a thicker bar.
struct WidgetHero: View {
    let kind: UsageWindow.Kind
    let window: UsageWindow?
    let prefs: Preferences
    let now: Date
    let moneySubtitle: String?
    /// 28 pt in the small family, larger where a family has the height
    /// (the all-accounts widget).
    var figureSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(window?.shortTitle ?? kind.shortName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if let window {
                    Text(verbatim: "\(Int(window.displayedPct(prefs.displayMode)))")
                        .font(Theme.figure(size: figureSize))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: "%")
                        .font(Theme.figure(size: figureSize * 0.46))
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    Text(verbatim: "--")
                        .font(Theme.figure(size: figureSize))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 4)
                Group {
                    if let resetsAt = window?.resetsAt {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.circlepath")
                            ResetLineText(resetsAt: resetsAt, style: prefs.resetStyle, now: now, bare: true)
                        }
                    } else if let moneySubtitle {
                        Text(moneySubtitle)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                height: 7,
                lit: true
            )
        }
        .accessibilityElement(children: .combine)
    }
}

/// A widget card's other windows, one line each: name, a thin bar, the
/// figure, in shared columns so the bars start and end together (the
/// app card's `CompactWindowRows`, at widget sizes).
struct WidgetCompactRows: View {
    let slots: [AccountCardLayout.Slot]
    let prefs: Preferences

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(slots, id: \.kind) { slot in
                let window = slot.window
                GridRow {
                    Text(window?.shortTitle ?? slot.kind.shortName)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .layoutPriority(1)
                    UsageBarView(
                        value: window?.displayedPct(prefs.displayMode),
                        tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                        height: 4
                    )
                    .frame(minWidth: 24)
                    .accessibilityHidden(true)
                    Text(verbatim: window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--")
                        .font(Theme.figure(size: 11))
                        .foregroundStyle(window == nil ? Theme.inkSecondary : Theme.ink)
                        .gridColumnAlignment(.trailing)
                }
            }
        }
    }
}
