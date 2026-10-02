#if os(macOS)
import SwiftUI
import UsageKit

/// Settings → "Menu bar": a live preview of the status item label on a
/// light and a dark menu bar, then everything that feeds it — which
/// account (2+ only) and window it reads, the style, and the three
/// modifiers. The preview renders the same `MenuBarLabel` from the same
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
                preview
                Divider().overlay(Theme.track)

                if model.accounts.count > 1 {
                    SegmentedPill(
                        options: model.accounts.map { ($0.account.accountID, $0.account.displayName) },
                        selection: primaryAccountBinding
                    )
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

                if prefs.menuBarStyle == .multi {
                    MetricChips(options: glanceOptions, selection: $prefs.menuBarMetrics)
                } else {
                    SegmentedPill(
                        options: glanceOptions.map { ($0, $0.shortName) },
                        selection: $prefs.glanceMetric
                    )
                }
                Divider().overlay(Theme.track)

                toggle("Red at 80% used", isOn: $prefs.menuBarTintsAtDanger)
                if prefs.menuBarStyle != .multi {
                    Divider().overlay(Theme.track)
                    toggle("Reset countdown", isOn: $prefs.menuBarShowsResetCountdown)
                }
                if model.accounts.count > 1 {
                    Divider().overlay(Theme.track)
                    toggle("Account name", isOn: $prefs.menuBarShowsAccountName)
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

    private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.ink)
        }
        .tint(Theme.accent)
    }

    private var glanceOptions: [UsageWindow.Kind] {
        UsageSnapshot.glanceOptions(
            for: model.primaryAccountUsage(preferredID: prefs.primaryAccountID)?.snapshot,
            modelSlotFallback: prefs.modelSlotFallback
        )
    }

    /// Writes through to `prefs.primaryAccountID`; reads through
    /// `UsageModel.primaryAccountUsage` so the picker always shows a
    /// connected account even if the stored id is stale (e.g. that account
    /// was disconnected elsewhere).
    private var primaryAccountBinding: Binding<String> {
        Binding(
            get: { model.primaryAccountUsage(preferredID: prefs.primaryAccountID)?.account.accountID ?? ClaudeKeychainCredentialSource.legacyAccountID },
            set: { prefs.primaryAccountID = $0 }
        )
    }

    private var footnote: String {
        var text = prefs.menuBarStyle == .multi
            ? String(localized: "Pick up to three windows to list side by side. The exact values are always in the tooltip.")
            : String(localized: "Pick which window the menu bar reads. Whatever the style, the exact value is always in the tooltip.")
        text += " " + String(localized: "For a system-wide shortcut, add \"Refresh Usage\" or \"Show Usage\" to the Shortcuts app and give it a key there — no extra permissions needed.")
        return text
    }
}

/// Multi-select row of window chips for the `multi` style — toggles
/// membership in `selection`, keeping the options' own order, never fewer
/// than one nor more than `MenuBarLabelModel.maxMetrics`.
private struct MetricChips: View {
    let options: [UsageWindow.Kind]
    @Binding var selection: [UsageWindow.Kind]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { kind in
                let isOn = selection.contains(kind)
                Button {
                    toggle(kind)
                } label: {
                    Text(kind.shortName)
                        .font(.subheadline.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Theme.ink : Theme.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isOn ? Theme.accentWash : Theme.track.opacity(0.6), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func toggle(_ kind: UsageWindow.Kind) {
        if selection.contains(kind) {
            guard selection.count > 1 else { return }
            selection.removeAll { $0 == kind }
        } else {
            guard selection.count < MenuBarLabelModel.maxMetrics else { return }
            selection = options.filter { selection.contains($0) || $0 == kind }
        }
    }
}
#endif
