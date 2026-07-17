import SwiftUI
import UsageKit

struct DashboardView: View {
    @Environment(UsageModel.self) private var model
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var showingSettings = false
    @State private var showingConnect = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header
                Text("AIMeter")
                    .font(Theme.displayTitle)
                    .foregroundStyle(Theme.ink)
                providerSection
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationDestination(for: String.self) { _ in
            ProviderDetailView()
        }
        #if os(iOS)
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
        }
        #endif
        .sheet(isPresented: $showingConnect) {
            ConnectClaudeSheet()
        }
    }

    private var header: some View {
        HStack {
            RoundIconButton(systemName: "gearshape") {
                #if os(macOS)
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
                #else
                showingSettings = true
                #endif
            }
            Spacer()
            RoundIconButton(systemName: "arrow.clockwise", isBusy: model.isRefreshing) {
                Task { await model.refresh() }
            }
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            providerHeader

            if model.needsConnection {
                Card {
                    VStack(spacing: 14) {
                        Text("Sign in to see your usage.")
                            .font(.callout)
                            .foregroundStyle(Theme.inkSecondary)
                        Button {
                            showingConnect = true
                        } label: {
                            Label("Connect", systemImage: "link")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(Theme.accent, in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        if let error = model.lastError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.danger)
                        }
                        WindowRowsList(snapshot: model.snapshot)
                        if let snapshot = model.snapshot {
                            Divider().overlay(Theme.track)
                            Text(UsageFormatting.updatedLabel(snapshot.fetchedAt))
                                .font(Theme.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
            }
        }
    }

    private var providerHeader: some View {
        NavigationLink(value: "claude") {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24, height: 24)
                    .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("Claude")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let plan = model.snapshot?.planName {
                    Text(plan.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.accentWash, in: Capsule())
                }
                Spacer()
                if !model.needsConnection {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.needsConnection)
    }
}

/// Floating circular icon button (dashboard header).
struct RoundIconButton: View {
    let systemName: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(width: 40, height: 40)
            .background(Theme.card, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}
