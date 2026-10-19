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
        let window = snapshot.window(for: prefs.glanceMetric)
        Gauge(value: min(window?.displayedPct(prefs.displayMode) ?? 0, 100), in: 0...100) {
            Text(caption)
        } currentValueLabel: {
            Text(window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    /// Compact subtitle under the ring — a rollover hint for the two rate
    /// windows (matching the space "5h"/"7d" fit), a currency glyph for
    /// Credits since that one has no fixed period, and the provider's own
    /// short name for a per-model window (e.g. "Fable" on Max) since
    /// there's no generic hint that fits every plan's model name.
    private var caption: String {
        switch prefs.glanceMetric {
        case .session: return String(localized: "5h")
        case .weekly: return String(localized: "7d")
        case .credits: return String(localized: "$")
        case .modelSpecific: return prefs.glanceMetric.shortName
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
                    Text(slot.kind.shortName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(slot.window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--")
                        .font(.caption.monospacedDigit().weight(.semibold))
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
            slot.window.map { "\(slot.kind.shortName) \(Int($0.displayedPct(prefs.displayMode)))%" }
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
        let window = snapshot.window(for: prefs.glanceMetric)
        let value = window?.displayedPct(prefs.displayMode)
        Text(value.map { "\(Int($0))%" } ?? "--")
            .font(.system(size: 22, weight: .semibold))
            .monospacedDigit()
            .widgetLabel {
                Gauge(value: min(value ?? 0, 100), in: 0...100) {
                    Text(prefs.glanceMetric.shortName)
                }
                .gaugeStyle(.accessoryLinearCapacity)
            }
    }
}
#endif
#endif
