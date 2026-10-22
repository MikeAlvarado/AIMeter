#if os(macOS)
import SwiftUI
import UsageKit

/// Settings → "Menu bar" (a tab of `MacSettingsView`): a live preview of
/// the status item label on a light and a dark menu bar, then everything
/// that feeds it — which account (2+ only) and window(s) it reads, the
/// style, and the three modifiers. The preview renders the same `MenuBarLabel` from the same
/// `MenuBarLabelModel.current` the `MenuBarExtra` uses, so what's shown
/// here is the truth, not a mock-up of it.
struct MenuBarSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Menu bar"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                // Whether it is there at all comes first: someone who
                // wants the icon gone looks for it here.
                MenuBarVisibilityToggle()
                Divider().overlay(Theme.track)
                preview
                Divider().overlay(Theme.track)

                if model.accounts.count > 1 {
                    MainAccountNote()
                    Divider().overlay(Theme.track)
                }

                HStack {
                    Text("Style")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Picker("", selection: $prefs.menuBarStyle) {
                        ForEach(MenuBarStyle.allCases, id: \.self) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .tint(Theme.accent)
                }
                Divider().overlay(Theme.track)

                // Titled, so the window choice never reads as one more
                // style or account control.
                VStack(alignment: .leading, spacing: 8) {
                    if prefs.menuBarStyle == .multi {
                        rowTitle(Text("Windows"))
                        MetricChips(options: glanceOptions, selection: $prefs.menuBarMetrics)
                    } else {
                        rowTitle(Text("Window"))
                        SegmentedPill(
                            options: glanceOptions.map { ($0, $0.shortName) },
                            selection: $prefs.glanceMetric
                        )
                    }
                }
                let rows = toggleRows
                if !rows.isEmpty {
                    Divider().overlay(Theme.track)
                }
                ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                    if index > 0 { Divider().overlay(Theme.track) }
                    switch row {
                    case .tint: toggle("Yellow above 70%, red above 85%", isOn: $prefs.menuBarTintsAtDanger)
                    case .countdown: toggle("Reset countdown", isOn: $prefs.menuBarShowsResetCountdown)
                    case .accountName: toggle("Account name", isOn: $prefs.menuBarShowsAccountName)
                    }
                }
            }
        }
        SectionFootnote(text: footnote)
    }

    /// The label twice, on a light and a dark strip, so a template glyph
    /// and the danger tint can both be judged against the bar they'll sit
    /// on. Decorative: every control it reflects is right below it.
    private var preview: some View {
        let label = MenuBarLabelModel.current(model: model, prefs: prefs)
        return HStack(spacing: 10) {
            previewStrip(label, scheme: .light)
            previewStrip(label, scheme: .dark)
        }
        .accessibilityHidden(true)
    }

    private func previewStrip(_ label: MenuBarLabelModel, scheme: ColorScheme) -> some View {
        MenuBarLabel(model: label)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                scheme == .light ? Color(white: 0.92) : Color(white: 0.16),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .environment(\.colorScheme, scheme)
    }

    private func rowTitle(_ text: Text) -> some View {
        text
            .font(Theme.rowTitle)
            .foregroundStyle(Theme.ink)
    }

    private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.ink)
        }
        .tint(Theme.accent)
    }

    private enum ToggleRow: Hashable {
        case tint, countdown, accountName
    }

    /// The switches under the window choice. The tint is the status
    /// item's own opt-in to the bars' colors, so it isn't offered while
    /// usage colors are off for every bar; the countdown has no place in
    /// `multi`; the name only tells two or more accounts apart.
    private var toggleRows: [ToggleRow] {
        var rows: [ToggleRow] = []
        if prefs.usageColors { rows.append(.tint) }
        if prefs.menuBarStyle != .multi { rows.append(.countdown) }
        if model.accounts.count > 1 { rows.append(.accountName) }
        return rows
    }

    private var glanceOptions: [UsageWindow.Kind] {
        UsageSnapshot.glanceOptions(
            for: model.glancePrimary(prefs)?.snapshot,
            modelSlotFallback: prefs.modelSlotFallback
        )
    }

    private var footnote: String {
        var text = prefs.menuBarStyle == .multi
            ? String(localized: "Pick up to three windows to list side by side. The exact values are always in the tooltip.")
            : String(localized: "Pick which window the menu bar reads. Whatever the style, the exact value is always in the tooltip.")
        text += " " + String(localized: "For a system-wide shortcut, add \"Refresh Usage\" or \"Show Usage\" to the Shortcuts app and give it a key there. No extra permissions needed.")
        return text
    }
}
#endif
