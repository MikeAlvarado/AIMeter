#if os(macOS)
import SwiftUI
import UsageKit

/// Label shown in the macOS menu bar: one account's usage at a glance, in
/// whichever `MenuBarStyle` the user picked. Everything it shows comes
/// from a `MenuBarLabelModel` (text, fill fraction, tint, accessibility
/// label — see that type for the rules); this view only draws it.
///
/// The gauge styles use the variable-value SF Symbol as the status item
/// always has; the bar and battery are drawn into an `NSImage` with
/// `ImageRenderer`, because a status item flattens arbitrary SwiftUI
/// shapes but renders an `Image(nsImage:)` faithfully. That image is a
/// *template* (so it adapts to a light or dark menu bar) except when the
/// danger tint applies, where it carries the real red. Either way the
/// exact value stays reachable through the tooltip and the accessibility
/// label — a menu bar with no room to spare is exactly where that matters.
struct MenuBarLabel: View {
    let model: MenuBarLabelModel

    var body: some View {
        HStack(spacing: 3) {
            switch model.style {
            case .gaugeWithPercent, .gaugeOnly:
                Image(systemName: "gauge.with.needle", variableValue: model.fraction)
            case .bar:
                Image(nsImage: MenuBarGlyph.bar(fraction: model.fraction, danger: model.tint == .danger))
            case .battery:
                Image(nsImage: MenuBarGlyph.battery(fraction: model.fraction, danger: model.tint == .danger))
            case .percentOnly, .multi:
                EmptyView()
            }
            if let text = model.text {
                Text(verbatim: text)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(model.tint == .danger ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(.primary))
        .help(valueLabel)
        .accessibilityLabel(valueLabel)
    }

    /// Peak state folds into the tooltip/accessibility text only — the
    /// status item is a single carefully tuned element, and this is the
    /// smallest way to surface "why is this moving faster than usual"
    /// without a second glyph. The popover header shows a visible badge
    /// instead, where there's room (`MenuBarView`).
    private var valueLabel: String {
        let peak = ClaudePeakStatus()
        return peak.isPeak ? "\(model.accessibilityLabel) · \(peak.title)" : model.accessibilityLabel
    }
}

/// A once-a-minute clock for the status item's reset countdown. Not a
/// `TimelineView`: inside a `MenuBarExtra` *label*, `TimelineView(.everyMinute)`
/// asks the extra's host to re-render again from inside the render it just
/// did, and on macOS 27 `MenuBarExtraController.init` never returns — the
/// app sat at 100 % CPU before finishing launching, with "Reset countdown"
/// on (1.6.0 shipped with it; reproduced 2026-10-08 on 27.0.1 and bisected
/// to that one preference). An observable date advanced by a main-actor
/// task at each minute boundary gives the label the same cadence with no
/// re-entrancy: the label reads `now` only while the countdown is on, so
/// nothing else re-evaluates on the clock.
@MainActor
@Observable
final class MinuteClock {
    private(set) var now = Date()
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init() {
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let wait = Self.nextTick(after: Date()).timeIntervalSinceNow
                try? await Task.sleep(for: .seconds(max(1, wait)))
                guard let self else { return }
                self.now = Date()
            }
        }
    }

    /// The next whole minute strictly after `date` (never `date` itself,
    /// so a tick on the boundary waits a full minute rather than zero).
    static func nextTick(after date: Date) -> Date {
        let minute: TimeInterval = 60
        let boundary = (date.timeIntervalSinceReferenceDate / minute).rounded(.down) * minute + minute
        return Date(timeIntervalSinceReferenceDate: boundary)
    }
}

extension MenuBarLabelModel {
    /// The label as the status item should show it right now: the primary
    /// account's snapshot through every menu bar preference. Shared by the
    /// `MenuBarExtra` label and the Settings preview, so the preview is the
    /// truth rather than a copy of it.
    @MainActor
    static func current(model: UsageModel, prefs: PreferencesModel, now: Date = Date()) -> MenuBarLabelModel {
        let usage = model.primaryAccountUsage(preferredID: prefs.primaryAccountID)
        let showsName = prefs.menuBarShowsAccountName && model.accounts.count > 1
        return MenuBarLabelModel(
            snapshot: usage?.snapshot,
            displayMode: prefs.displayMode,
            style: prefs.menuBarStyle,
            metric: prefs.glanceMetric,
            metrics: prefs.menuBarMetrics,
            modelSlotFallback: prefs.modelSlotFallback,
            tintsAtDanger: prefs.menuBarTintsAtDanger,
            showsCountdown: prefs.menuBarShowsResetCountdown,
            accountName: showsName ? usage?.account.displayName : nil,
            now: now
        )
    }
}

/// The two drawn glyphs, rendered at the screen's scale. Template images
/// are drawn in black and let AppKit recolor them for the menu bar; a
/// danger image carries `Theme.danger` itself and is marked non-template
/// so that color survives.
@MainActor
enum MenuBarGlyph {
    static func bar(fraction: Double, danger: Bool) -> NSImage {
        render(BarGlyph(fraction: fraction, color: danger ? Theme.danger : .black), template: !danger)
    }

    static func battery(fraction: Double, danger: Bool) -> NSImage {
        render(BatteryGlyph(fraction: fraction, color: danger ? Theme.danger : .black), template: !danger)
    }

    private static func render<Content: View>(_ content: Content, template: Bool) -> NSImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 22, height: 10))
        image.isTemplate = template
        return image
    }
}

private struct BarGlyph: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().stroke(color, lineWidth: 1)
            Capsule()
                .fill(color)
                .frame(width: max(0, (22 - 4) * fraction))
                .padding(2)
        }
        .frame(width: 22, height: 8)
        .padding(.vertical, 3)
    }
}

private struct BatteryGlyph: View {
    let fraction: Double
    let color: Color

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .stroke(color, lineWidth: 1)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(color)
                    .frame(width: max(0, (20 - 4) * fraction))
                    .padding(2)
            }
            .frame(width: 20, height: 10)
            RoundedRectangle(cornerRadius: 0.5)
                .fill(color)
                .frame(width: 1.5, height: 4)
        }
        .padding(.vertical, 2)
    }
}
#endif
