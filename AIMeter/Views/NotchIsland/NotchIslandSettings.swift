#if os(macOS)
import AppKit
import SwiftUI
import UsageKit

/// Settings → "Notch island", above "Menu bar": a live preview of the
/// collapsed row on the real silhouette (from the same
/// `NotchIslandModel.current` the panel draws — the truth, not a mock),
/// the on/off toggle, which side(s) of the notch the wings use, the
/// windows they list, and whether hovering opens it.
struct NotchIslandSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @State private var previewMode: NotchIslandGeometry.Mode = .pill

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
                    Text("Show usage in the notch")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)

                if hasNotch {
                    Divider().overlay(Theme.track)
                    SegmentedPill(
                        options: NotchIslandLayout.allCases.map { ($0, $0.label) },
                        selection: $prefs.notchIslandLayout
                    )
                }
                Divider().overlay(Theme.track)
                MetricChips(options: glanceOptions, selection: $prefs.notchIslandMetrics, maxCount: NotchIslandModel.maxMetrics)
                Divider().overlay(Theme.track)

                Toggle(isOn: $prefs.notchIslandExpandsOnHover) {
                    Text("Peek on hover")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)
            }
        }
        .onAppear { previewMode = Self.previewMode() }
        SectionFootnote(text: footnote)
    }

    /// The peek — what the user will actually see on hover: the wings
    /// open beside the notch on the real silhouette over a neutral strip.
    /// Decorative: every control it reflects is right below it.
    private var preview: some View {
        let island = NotchIslandModel.current(model: model, prefs: prefs)
        let notchWidth: CGFloat
        if case .notch(let rect) = previewMode { notchWidth = rect.width } else { notchWidth = 0 }
        return CollapsedRow(island: island, mode: previewMode, notchWidth: notchWidth)
            .frame(height: NotchIslandGeometry.barHeight(Self.previewScreen, mode: previewMode))
            .notchIslandSurface(mode: previewMode)
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }

    private var hasNotch: Bool {
        if case .notch = previewMode { return true }
        return false
    }

    private var glanceOptions: [UsageWindow.Kind] {
        UsageSnapshot.glanceOptions(
            for: model.primaryAccountUsage(preferredID: prefs.primaryAccountID)?.snapshot,
            modelSlotFallback: prefs.modelSlotFallback
        )
    }

    private var footnote: String {
        var text = String(localized: "Rest the cursor on the notch and the wings open with your limits; stay a moment longer, or click, and everything opens. Turning the island on hides the menu bar icon; turning it off brings the icon back. Everything it shows is also in the menu bar popover and the Dashboard.")
        if !hasNotch {
            text += " " + String(localized: "This Mac has no notch, so AIMeter shows a floating pill at the top of the screen instead.")
        }
        return text
    }

    /// The real screen, and its mode with the notch gap narrowed to a
    /// token so the row fits a Settings card.
    private static var previewScreen: NotchIslandGeometry.Screen {
        let screens = NSScreen.screens.map(NotchIslandController.describe)
        guard let index = NotchIslandGeometry.target(screens: screens) else {
            return NotchIslandGeometry.Screen(frame: .zero, safeTop: NSStatusBar.system.thickness, auxLeft: nil, auxRight: nil)
        }
        return screens[index]
    }

    private static func previewMode() -> NotchIslandGeometry.Mode {
        switch NotchIslandGeometry.mode(for: previewScreen) {
        case .notch(let rect): return .notch(CGRect(x: 0, y: 0, width: min(rect.width, 120), height: rect.height))
        case .pill: return .pill
        }
    }
}
#endif
