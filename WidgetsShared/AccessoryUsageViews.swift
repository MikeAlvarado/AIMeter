import SwiftUI
import WidgetKit
import UsageKit

// The accessory families, system-tinted: iOS's Lock Screen and the
// Watch's complications draw the same three (the Watch adds the corner).
// Compiled into both widget extensions (`WidgetsShared/`), never into the
// Mac's families.

#if !os(macOS)
struct CircularUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences

    var body: some View {
        let kind = UsageSnapshot.glanceMetric(prefs.glanceMetric, for: snapshot, modelSlotFallback: prefs.modelSlotFallback)
        let window = snapshot.window(for: kind)
        Gauge(value: min(window?.displayedPct(prefs.displayMode) ?? 0, 100), in: 0...100) {
            Text(caption)
        } currentValueLabel: {
            Text(window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    /// Compact subtitle under the ring — the window's length for the two
    /// rate windows ("5h", "7d", "30d" for a month, the space that fits),
    /// a currency glyph for Credits since that one has no fixed period,
    /// and the provider's own short name for a per-model window (e.g.
    /// "Fable" on Max) or a quota ("Premium"), since no generic hint fits
    /// every plan's names. The metric falls back to the account's first
    /// window when it reports no window of the chosen kind.
    private var caption: String {
        let kind = UsageSnapshot.glanceMetric(prefs.glanceMetric, for: snapshot, modelSlotFallback: prefs.modelSlotFallback)
        let duration = snapshot.window(for: kind)?.effectiveDuration
        switch kind {
        case .session:
            return String(localized: "\(UsageWindow.Kind.hours(duration))h")
        case .weekly:
            switch UsageWindow.Kind.period(duration) {
            case .week: return String(localized: "7d")
            case .month: return String(localized: "30d")
            case .days(let days): return String(localized: "\(days)d")
            }
        case .credits: return String(localized: "$")
        case .modelSpecific, .quota: return kind.shortName
        }
    }
}

struct RectangularUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(WindowSlots(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback).slots, id: \.kind) { slot in
                HStack {
                    Text(slot.window?.shortTitle ?? slot.kind.shortName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(slot.window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--")
                        .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                }
            }
        }
    }
}

struct InlineUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences

    var body: some View {
        let parts = WindowSlots(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback).slots.compactMap { slot in
            slot.window.map { "\($0.shortTitle) \(Int($0.displayedPct(prefs.displayMode)))%" }
        }
        Text(parts.joined(separator: " · "))
    }
}

#if os(watchOS)
/// The corner complication: the glance window's figure, with a short
/// gauge along the bezel as its label.
struct CornerUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences

    var body: some View {
        let kind = UsageSnapshot.glanceMetric(prefs.glanceMetric, for: snapshot, modelSlotFallback: prefs.modelSlotFallback)
        let window = snapshot.window(for: kind)
        let value = window?.displayedPct(prefs.displayMode)
        Text(value.map { "\(Int($0))%" } ?? "--")
            .font(Theme.figure(size: 22))
            .widgetLabel {
                Gauge(value: min(value ?? 0, 100), in: 0...100) {
                    Text(window?.shortTitle ?? kind.shortName)
                }
                .gaugeStyle(.accessoryLinearCapacity)
            }
    }
}
#endif
#endif
