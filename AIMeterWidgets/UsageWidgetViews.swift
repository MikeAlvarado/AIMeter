import SwiftUI
import WidgetKit
import UsageKit

/// System families show a "Claude" header plus capsule bars with reset
/// times, mirroring the dashboard rows. All views honor the
/// Remaining/Used and Relative/Absolute preferences from the App Group.
struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemMedium:
                    MediumUsageView(snapshot: snapshot, prefs: entry.prefs)
                #if os(iOS)
                case .accessoryCircular:
                    CircularUsageView(snapshot: snapshot, prefs: entry.prefs)
                case .accessoryRectangular:
                    RectangularUsageView(snapshot: snapshot, prefs: entry.prefs)
                case .accessoryInline:
                    InlineUsageView(snapshot: snapshot, prefs: entry.prefs)
                #endif
                default:
                    SmallUsageView(snapshot: snapshot, prefs: entry.prefs)
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

/// "Claude" title with the logo; shows a staleness hint on the trailing
/// edge so it never costs an extra row. Widget fonts are fixed sizes on
/// purpose: text styles scale with the device's Dynamic Type and overflow
/// the fixed widget height on real hardware.
private struct WidgetHeader: View {
    let snapshot: UsageSnapshot

    var body: some View {
        HStack(spacing: 5) {
            ProviderIdentityView(
                name: "Claude",
                iconSize: 15,
                iconCornerRadius: 3.5,
                font: .system(size: 12, weight: .semibold),
                nameColor: Theme.ink,
                planName: nil
            )
            Spacer(minLength: 0)
            if snapshot.isStale {
                HStack(spacing: 2) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(snapshot.fetchedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                }
                .font(.system(size: 8))
                .foregroundStyle(Theme.inkSecondary.opacity(0.8))
            }
        }
    }
}

/// One usage window as a labeled bar with its reset line under it, like
/// the dashboard rows: name + percent, capsule bar, "Resets in 4h 10m".
private struct WindowBarRow: View {
    let kind: UsageWindow.Kind
    let window: UsageWindow?
    let prefs: Preferences
    var showsReset = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(kind.shortName)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 4)
                Text(window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "—")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint ?? Theme.accent
            )
            if showsReset, let resetsAt = window?.resetsAt {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.circlepath")
                    Text(UsageFormatting.resetLabel(for: resetsAt, style: prefs.resetStyle))
                }
                .font(.system(size: 9))
                .foregroundStyle(Theme.inkSecondary.opacity(0.9))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Header at the top, then each window row in an equal flexible slice of
/// the remaining height — the content spreads to fill the family instead
/// of clumping at the top (small) or leaving a gap below (medium).
/// Consecutive windows sharing one reset date (Weekly and Weekly·Fable)
/// show the "Resets in" line once, under the last bar of the group.
private struct WindowBarList: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences
    let count: Int

    var body: some View {
        let slots = Array(WindowSlots(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback).slots.prefix(count))
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(snapshot: snapshot)
            ForEach(Array(slots.enumerated()), id: \.element.kind) { index, slot in
                WindowBarRow(
                    kind: slot.kind,
                    window: slot.window,
                    prefs: prefs,
                    showsReset: WindowSlots.showsReset(at: index, in: slots)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Small: header plus all three windows, same as medium but narrow.
struct SmallUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences

    var body: some View {
        WindowBarList(snapshot: snapshot, prefs: prefs, count: 3)
    }
}

/// Medium: header plus all three windows as bars.
struct MediumUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences

    var body: some View {
        WindowBarList(snapshot: snapshot, prefs: prefs, count: 3)
    }
}

// MARK: - Accessory families (iOS Lock Screen; system-tinted rendering)

#if os(iOS)
struct CircularUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences

    var body: some View {
        let session = snapshot.sessionWindow
        Gauge(value: min(session?.displayedPct(prefs.displayMode) ?? 0, 100), in: 0...100) {
            Text("5h")
        } currentValueLabel: {
            Text(session.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "—")
        }
        .gaugeStyle(.accessoryCircularCapacity)
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
                    Text(slot.window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "—")
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
#endif
