#if os(macOS)
import SwiftUI
import UsageKit

/// Label shown in the macOS menu bar: one window's usage at a glance —
/// Session by default, or whichever window the user picked as
/// `glanceMetric` in Claude's Provider Detail (e.g. Credits, or a
/// per-model window on Max) — honoring the Remaining/Used display
/// preference.
///
/// The gauge is always drawn; `showsPercentage` (Settings → Menu bar) only
/// decides whether the number is spelled out beside it. Its variable value
/// tracks the same figure the text would show, so the two never disagree
/// and icon-only mode still reads as a rough level rather than a static
/// glyph. Either way the exact value stays reachable through the tooltip
/// and the accessibility label — a menu bar with no room to spare is
/// exactly where that matters.
struct MenuBarLabel: View {
    let snapshot: UsageSnapshot?
    let displayMode: DisplayMode
    let metric: UsageWindow.Kind
    let showsPercentage: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.needle", variableValue: gaugeValue)
            if showsPercentage, let percent {
                Text(verbatim: "\(percent)%")
                    .monospacedDigit()
            }
        }
        .help(valueLabel)
        .accessibilityLabel(valueLabel)
    }

    private var window: UsageWindow? { snapshot?.window(for: metric) }

    private var percent: Int? {
        window.map { Int($0.displayedPct(displayMode)) }
    }

    /// 0–1 for the symbol's variable rendering. Follows the *displayed*
    /// figure rather than raw usage, so a "Remaining" reading of 58% shows a
    /// gauge that's 58% full instead of contradicting its own label.
    private var gaugeValue: Double {
        guard let window else { return 0 }
        return min(max(window.displayedPct(displayMode) / 100, 0), 1)
    }

    private var valueLabel: String {
        guard let percent else {
            return String(localized: "AIMeter — no usage data yet")
        }
        return String(localized: "\(metric.shortName): \(percent)% \(displayMode.label)")
    }
}

struct MenuBarView: View {
    @Environment(UsageModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var showingConnect = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            header
            Divider().overlay(Theme.track)

            if model.needsConnection {
                DisconnectedPrompt(buttonLabel: "Connect Claude Code", verticalPadding: 10) {
                    showingConnect = true
                }
            } else {
                WindowRowsList(snapshot: model.snapshot)
                UsageStatusFooter(snapshot: model.snapshot, error: model.lastError, showsDividers: false)
            }

            Divider().overlay(Theme.track)

            HStack {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)

                Spacer()

                Button("Settings…") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
        .background(Theme.background)
        .sheet(isPresented: $showingConnect) {
            ConnectClaudeSheet()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ProviderIdentityView(
                name: "Claude",
                iconSize: 20,
                iconCornerRadius: 5,
                font: Theme.sectionHeader,
                nameColor: Theme.inkSecondary,
                planName: model.snapshot?.planName
            )
            Spacer()
        }
    }
}
#endif
