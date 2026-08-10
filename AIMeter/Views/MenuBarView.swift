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

    /// Peak state folds into the tooltip/accessibility text only — the
    /// status item itself is a carefully tuned single gauge (see the type
    /// doc above), and this is the smallest way to surface "why is this
    /// moving faster than usual" without adding a second glyph to the
    /// smallest surface in the app. The popover header shows a visible
    /// badge instead, where there's room (`MenuBarView.header`).
    private var valueLabel: String {
        let peak = ClaudePeakStatus()
        let base = percent.map {
            String(localized: "\(metric.shortName): \($0)% \(displayMode.label)")
        } ?? String(localized: "AIMeter — no usage data yet")
        return peak.isPeak ? "\(base) · \(peak.title)" : base
    }
}

struct MenuBarView: View {
    @Environment(UsageModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var showingConnect = false

    private var peak: ClaudePeakStatus { ClaudePeakStatus() }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            if peak.isPeak {
                peakBadgeRow
                Divider().overlay(Theme.track)
            }

            if model.needsConnection {
                DisconnectedPrompt(buttonLabel: "Connect Claude Code", verticalPadding: 10) {
                    showingConnect = true
                }
            } else {
                // Height-capped rather than growing unbounded — a handful
                // of accounts should still fit the popover; more scrolls.
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        ForEach(model.accounts) { usage in
                            AccountSectionView(
                                usage: usage,
                                iconSize: 20,
                                iconCornerRadius: 5,
                                font: Theme.sectionHeader,
                                linksToDetail: false,
                                showsStatusDividers: false
                            )
                        }
                        addAccountButton
                    }
                }
                .frame(maxHeight: 360)
            }

            Divider().overlay(Theme.track)

            HStack {
                // The popover has no navigation stack, so it can't reach
                // Provider Detail (Peak hours, Forecast, per-account
                // notifications, disconnect) — this is the only way back to
                // the Dashboard window that can. `revealMainWindow` reopens
                // it even if `AppDelegate` closed it at launch (the common
                // hidden-Dock-icon case), since the scene registers its
                // reopen hook on first appearance, before any such close.
                Button {
                    AppChrome.revealMainWindow()
                } label: {
                    Image(systemName: "macwindow")
                }
                .help(String(localized: "Open AIMeter"))
                .accessibilityLabel(Text("Open AIMeter"))

                Button {
                    Task { await model.refreshAll() }
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

    /// Once at least one account is connected, this is the *only* way to add
    /// another from the menu bar — the Dashboard window (which has its own
    /// copy of this button) isn't reachable from here, and stays closed by
    /// default whenever the Dock icon is hidden (see `AppDelegate`), which
    /// is the common case for a menu-bar-first setup.
    private var addAccountButton: some View {
        Button {
            showingConnect = true
        } label: {
            Label("Add account", systemImage: "plus.circle")
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    private var peakBadgeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(Theme.danger)
            Text(peak.title)
                .font(Theme.sectionHeader)
                .foregroundStyle(Theme.ink)
            Spacer()
        }
        .help(peak.subtitle)
        .accessibilityElement(children: .combine)
    }
}
#endif
