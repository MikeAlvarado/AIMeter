#if os(macOS)
import SwiftUI
import UsageKit

/// Label shown in the macOS menu bar: session usage at a glance, honoring
/// the Remaining/Used display preference.
struct MenuBarLabel: View {
    let snapshot: UsageSnapshot?
    let displayMode: DisplayMode

    var body: some View {
        if let session = snapshot?.sessionWindow {
            Text("\(Int(session.displayedPct(displayMode)))%")
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
                Text("Sign in to see your usage.")
                    .font(.callout)
                    .foregroundStyle(Theme.inkSecondary)
                Button {
                    showingConnect = true
                } label: {
                    Label("Connect Claude Code", systemImage: "link")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Theme.accent, in: Capsule())
            } else {
                WindowRowsList(snapshot: model.snapshot)
                if let error = model.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                }
                if let snapshot = model.snapshot {
                    Text(UsageFormatting.updatedLabel(snapshot.fetchedAt))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
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
