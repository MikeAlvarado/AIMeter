import SwiftUI
import WidgetKit
import UsageKit

/// Medium family: the account's windows side by side, each a column with
/// a big percentage over its bar — the layout the extra width is for,
/// instead of the small widget's rows stretched wide. Two columns when
/// the account reports (or the third-row fallback yields) two slots,
/// three when it has a per-model window or credits; the value font
/// steps down for three so "100% left" still fits a column.
struct MediumUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences
    let date: Date
    let accountID: String
    let accountName: String

    var body: some View {
        let slots = WindowSlots(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback).slots
        let wide = slots.count <= 2
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(snapshot: snapshot, date: date, accountID: accountID, accountName: accountName, planName: snapshot.planName)
            Spacer(minLength: 6)
            HStack(alignment: .top, spacing: wide ? 16 : 10) {
                ForEach(slots, id: \.kind) { slot in
                    WindowColumn(
                        kind: slot.kind,
                        window: slot.window,
                        prefs: prefs,
                        valueSize: wide ? 28 : 22,
                        moneySubtitle: prefs.creditsAmountSubtitle(for: slot.kind, snapshot: snapshot)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One window as a column: name, the big figure with its "left"/"used"
/// suffix, the bar, and a subtitle — the reset line, the optional credits
/// amount, or "Not available" for a slot the account doesn't report.
/// Every column shows its own reset line: the grouped-reset rule
/// (`WindowSlots.showsReset`) is for stacked rows, where one line can sit
/// under a group; side by side, a column with nothing under its bar
/// would just look unfinished.
private struct WindowColumn: View {
    let kind: UsageWindow.Kind
    let window: UsageWindow?
    let prefs: Preferences
    let valueSize: CGFloat
    let moneySubtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kind.shortName)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let window {
                    Text("\(Int(window.displayedPct(prefs.displayMode)))%")
                        .font(.system(size: valueSize, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Text(prefs.displayMode.suffix)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    Text("—")
                        .font(.system(size: valueSize, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            // Fixed height, so the bars line up across columns whatever
            // the glyphs above them (a dash measures shorter than digits).
            .frame(height: ceil(valueSize * 1.2), alignment: .leading)
            .padding(.top, 2)
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint ?? Theme.accent
            )
            .padding(.top, 7)
            subtitle
                .font(.system(size: 9))
                .foregroundStyle(Theme.inkSecondary.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 5)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var subtitle: some View {
        if let resetsAt = window?.resetsAt {
            HStack(spacing: 3) {
                Image(systemName: "arrow.circlepath")
                Text(UsageFormatting.resetLabel(for: resetsAt, style: prefs.resetStyle))
            }
        } else if let moneySubtitle {
            HStack(spacing: 3) {
                Image(systemName: "dollarsign.circle")
                Text(moneySubtitle)
            }
        } else if window == nil {
            Text("Not available")
        } else {
            // A window with no reset date (an idle session): keep the
            // column's height so the bars across columns stay aligned.
            Text(" ")
        }
    }
}
