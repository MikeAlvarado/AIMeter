#if os(macOS)
import SwiftUI
import UsageKit

/// Label shown in the macOS menu bar: one window's usage at a glance —
/// Session by default, or whichever window the user picked as
/// `glanceMetric` in Claude's Provider Detail (e.g. Credits, or a
/// per-model window on Max) — honoring the Remaining/Used display
/// preference.
struct MenuBarLabel: View {
    let snapshot: UsageSnapshot?
    let displayMode: DisplayMode
    let metric: UsageWindow.Kind

    var body: some View {
        if let window = snapshot?.window(for: metric) {
            Text("\(Int(window.displayedPct(displayMode)))%")
        } else {
            Image(systemName: "gauge.with.needle")
        }
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
