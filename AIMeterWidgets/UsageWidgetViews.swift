import SwiftUI
import WidgetKit
import UsageKit

/// All widget families render the three fixed Claude slots (session,
/// weekly, top model) and honor the Remaining/Used and Relative/Absolute
/// preferences from the App Group.
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

struct SmallUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(WindowSlots(snapshot: snapshot).slots, id: \.kind) { slot in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(slot.kind.shortName)
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                        Spacer()
                        Text(percentText(slot.window))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    UsageBarView(
                        value: slot.window?.displayedPct(prefs.displayMode),
                        tint: slot.window?.tint ?? Theme.accent
                    )
                }
            }
            if snapshot.isStale {
                StaleFooter(fetchedAt: snapshot.fetchedAt)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func percentText(_ window: UsageWindow?) -> String {
        window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "—"
    }
}

struct MediumUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(WindowSlots(snapshot: snapshot).slots, id: \.kind) { slot in
                    RingColumn(kind: slot.kind, window: slot.window, prefs: prefs)
                        .frame(maxWidth: .infinity)
                }
            }
            if snapshot.isStale {
                StaleFooter(fetchedAt: snapshot.fetchedAt)
            }
        }
    }
}

private struct RingColumn: View {
    let kind: UsageWindow.Kind
    let window: UsageWindow?
    let prefs: Preferences

    var body: some View {
        VStack(spacing: 4) {
            Gauge(value: min(window?.displayedPct(prefs.displayMode) ?? 0, 100), in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                Text(window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "—")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(window?.tint ?? Theme.track)
            .scaleEffect(0.9)

            Text(kind.shortName)
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)

            if let resetsAt = window?.resetsAt {
                Text(resetText(resetsAt))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.inkSecondary.opacity(0.8))
            }
        }
    }

    private func resetText(_ date: Date) -> String {
        switch prefs.resetStyle {
        case .relative:
            return UsageFormatting.relativeString(from: Date(), to: date)
        case .absolute:
            return date.formatted(date: .omitted, time: .shortened)
        }
    }
}

private struct StaleFooter: View {
    let fetchedAt: Date

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.arrow.circlepath")
            Text(fetchedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
        }
        .font(.system(size: 9))
        .foregroundStyle(Theme.inkSecondary.opacity(0.8))
        .frame(maxWidth: .infinity, alignment: .trailing)
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
            ForEach(WindowSlots(snapshot: snapshot).slots, id: \.kind) { slot in
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
        let parts = WindowSlots(snapshot: snapshot).slots.compactMap { slot in
            slot.window.map { "\(slot.kind.shortName) \(Int($0.displayedPct(prefs.displayMode)))%" }
        }
        Text(parts.joined(separator: " · "))
    }
}
#endif
