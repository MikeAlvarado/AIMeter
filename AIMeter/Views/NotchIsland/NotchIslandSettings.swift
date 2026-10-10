#if os(macOS)
import AppKit
import SwiftUI
import UsageKit

/// Settings → "Notch island", above "Menu bar": a live preview of the
/// island as it is on this screen (from the same `NotchIslandModel.current`
/// the panel draws — the truth, not a mock), the on/off toggle, which
/// side(s) of the notch the wings use, the windows they list, how hovering
/// opens it and whether captures leave it out; then "Screens without a
/// notch": the form (a drawn notch or a pill), its height, and when it
/// steps out of sight. The options follow boring.notch's and Atoll's
/// where those apply to AIMeter's island (see "Notch island prefs" in
/// the repo-root CLAUDE.md for which, and which were left out).
struct NotchIslandSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    /// The island's screen, read when the section appears.
    @State private var screen = NotchIslandSettings.islandScreen

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Notch island"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                preview
                Divider().overlay(Theme.track)

                Toggle(isOn: Binding(
                    get: { prefs.notchIslandEnabled },
                    set: { enabled in
                        prefs.setNotchIsland(enabled: enabled)
                        AppChrome.setNotchIsland(enabled: enabled)
                    }
                )) {
                    rowTitle("Show usage in the notch")
                }
                .tint(Theme.accent)

                if hasNotch {
                    Divider().overlay(Theme.track)
                    SegmentedPill(
                        options: NotchIslandLayout.allCases.map { ($0, $0.label) },
                        selection: $prefs.notchIslandLayout
                    )
                }
                if model.accounts.count > 1 {
                    // The wings are one account's; the chips below are
                    // that account's windows.
                    Divider().overlay(Theme.track)
                    PrimaryAccountPicker()
                }
                Divider().overlay(Theme.track)
                MetricChips(options: glanceOptions, selection: $prefs.notchIslandMetrics, maxCount: NotchIslandModel.maxMetrics)
                Divider().overlay(Theme.track)

                Toggle(isOn: $prefs.notchIslandExpandsOnHover) {
                    rowTitle("Peek on hover")
                }
                .tint(Theme.accent)
                if prefs.notchIslandExpandsOnHover {
                    sliderRow(
                        "Hover delay",
                        accessibilityLabel: "Hover delay",
                        value: $prefs.notchIslandHoverDelay,
                        range: NotchIslandInteraction.dwellRange,
                        step: 0.05,
                        label: Self.seconds(prefs.notchIslandHoverDelay)
                    )
                }
                Divider().overlay(Theme.track)
                Toggle(isOn: $prefs.notchIslandHiddenFromCapture) {
                    rowTitle("Hide from screenshots and recordings")
                }
                .tint(Theme.accent)
            }
        }
        .onAppear { screen = Self.islandScreen }
        SectionFootnote(text: String(localized: "Rest the cursor on the notch and the wings open with your limits; stay a moment longer, or click, and everything opens. Turning the island on hides the menu bar icon; turning it off brings the icon back. Everything it shows is also in the menu bar popover and the Dashboard."))

        SectionHeader(title: String(localized: "Screens without a notch"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    rowTitle("Style")
                    SegmentedPill(
                        options: NotchIslandForm.allCases.map { ($0, $0.label) },
                        selection: $prefs.notchIslandForm
                    )
                    Text(prefs.notchIslandForm.caption)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Divider().overlay(Theme.track)

                VStack(alignment: .leading, spacing: 8) {
                    rowTitle("Height")
                    SegmentedPill(
                        options: NotchIslandHeightMode.allCases.map { ($0, $0.label) },
                        selection: $prefs.notchIslandHeightMode
                    )
                    if prefs.notchIslandHeightMode == .custom {
                        sliderRow(
                            nil,
                            accessibilityLabel: "Height",
                            value: $prefs.notchIslandCustomHeight,
                            range: Double(NotchIslandGeometry.heightRange.lowerBound)...Double(NotchIslandGeometry.heightRange.upperBound),
                            step: 1,
                            label: String(localized: "\(Int(prefs.notchIslandCustomHeight)) pt")
                        )
                    }
                }
                Divider().overlay(Theme.track)

                Toggle(isOn: $prefs.notchIslandHidesUntilHover) {
                    rowTitle("Hide until hovered")
                }
                .tint(Theme.accent)
                Divider().overlay(Theme.track)
                Toggle(isOn: $prefs.notchIslandHidesInFullScreen) {
                    rowTitle("Hide in full screen")
                }
                .tint(Theme.accent)
            }
        }
        SectionFootnote(text: String(localized: "A Mac without a notch, or a MacBook closed on an external display, gets an island drawn at the top of the screen: a notch fused to the edge, or a pill floating in the menu bar. Hidden, it comes back when the cursor reaches its place; in full screen there is no menu bar to sit in, so it waits there too."))
    }

    // MARK: - Preview

    /// The island as this screen shows it with the cursor on it: the
    /// wings beside the real notch's silhouette, or the drawn notch or
    /// pill with its row, at the chosen height, over a neutral strip.
    /// Decorative: every control it reflects is right below it.
    private var preview: some View {
        let island = NotchIslandModel.current(model: model, prefs: prefs)
        let options = prefs.notchIslandOptions
        let mode = Self.previewMode(screen: screen, options: options)
        let notchWidth: CGFloat
        if case .notch(let rect) = mode { notchWidth = rect.width } else { notchWidth = 0 }
        let barHeight = NotchIslandGeometry.barHeight(screen, mode: mode, options: options)
        return CollapsedRow(island: island, mode: mode, notchWidth: notchWidth)
            .frame(height: barHeight)
            .notchIslandSurface(mode: mode, barHeight: barHeight)
            .environment(\.notchIslandRowScale, NotchIslandGeometry.rowScale(screen, mode: mode, options: options))
            .environment(\.colorScheme, .dark)
            .padding(.top, NotchIslandGeometry.topInset(screen, mode: mode, options: options))
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.snappy(duration: 0.2), value: options)
            .accessibilityHidden(true)
    }

    private var hasNotch: Bool {
        if case .notch = NotchIslandGeometry.mode(for: screen) { return true }
        return false
    }

    private var glanceOptions: [UsageWindow.Kind] {
        UsageSnapshot.glanceOptions(
            for: model.primaryAccountUsage(preferredID: prefs.primaryAccountID)?.snapshot,
            modelSlotFallback: prefs.modelSlotFallback
        )
    }

    // MARK: - Rows

    private func rowTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Theme.rowTitle)
            .foregroundStyle(Theme.ink)
    }

    /// A slider with its value at the trailing edge, the same shape as the
    /// near-limit threshold's in the notification cards. Quantized in the
    /// binding rather than with `step:`, which draws a tick per step — 21
    /// of them for the hover delay, a comb under the track.
    private func sliderRow(
        _ title: LocalizedStringKey?,
        accessibilityLabel: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        label: String
    ) -> some View {
        let quantized = Binding<Double>(
            get: { value.wrappedValue },
            set: { value.wrappedValue = ($0 / step).rounded() * step }
        )
        return HStack(spacing: 10) {
            if let title {
                Text(title)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Slider(value: quantized, in: range)
                .tint(Theme.accent)
                // The visible title is a separate Text (or the row's
                // header); VoiceOver needs the name on the slider itself,
                // and the value it reads is the label beside it.
                .accessibilityLabel(Text(accessibilityLabel))
                .accessibilityValue(Text(label))
            Text(label)
                .font(Theme.caption.monospacedDigit())
                .foregroundStyle(Theme.ink)
                .frame(width: 52, alignment: .trailing)
        }
    }

    /// "0.25 s", in the user's locale.
    private static func seconds(_ value: Double) -> String {
        Measurement(value: value, unit: UnitDuration.seconds)
            .formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2))))
    }

    // MARK: - Screen

    /// The island's screen, as the controller picks it.
    private static var islandScreen: NotchIslandGeometry.Screen {
        let screens = NSScreen.screens.map(NotchIslandController.describe)
        guard let index = NotchIslandGeometry.target(screens: screens) else {
            return NotchIslandGeometry.Screen(frame: .zero, safeTop: NSStatusBar.system.thickness, auxLeft: nil, auxRight: nil)
        }
        return screens[index]
    }

    /// The island's mode on that screen, with the notch gap narrowed to a
    /// token so the wings fit a Settings card.
    private static func previewMode(screen: NotchIslandGeometry.Screen, options: NotchIslandGeometry.Options) -> NotchIslandGeometry.Mode {
        switch NotchIslandGeometry.mode(for: screen, form: options.form) {
        case .notch(let rect): return .notch(CGRect(x: 0, y: 0, width: min(rect.width, 120), height: rect.height))
        case let other: return other
        }
    }
}
#endif
