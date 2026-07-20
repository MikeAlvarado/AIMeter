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
                providerSection
            }
            .padding(20)
        }
        .background(Theme.background)
        // Soft tap when a refresh kicks off — pull gesture or button alike.
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.isRefreshing) { _, isRefreshing in
            isRefreshing
        }
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
        ZStack {
            // Small centered app title — present but never competing with
            // the usage content below.
            Text(verbatim: "AIMeter")
                .font(.system(.headline, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
            HStack {
                headerButtons
            }
        }
    }

    private var headerButtons: some View {
        HStack {
            RoundIconButton(systemName: "gearshape") {
                #if os(macOS)
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
                #else
                showingSettings = true
                #endif
            }
            .accessibilityLabel(Text("Settings"))
            Spacer()
            RoundIconButton(systemName: "arrow.clockwise", isBusy: model.isRefreshing) {
                Task { await model.refresh() }
            }
            .accessibilityLabel(Text("Refresh"))
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
                        WindowRowsList(snapshot: model.snapshot)
                        if let error = model.lastError {
                            Divider().overlay(Theme.track)
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.danger)
                        }
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
                Image("ClaudeIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("Claude")
                    .font(Theme.sectionHeader)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                if let plan = model.snapshot?.planName {
                    Text(plan.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Theme.track.opacity(0.7), in: Capsule())
                }
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

/// Floating circular icon button (dashboard header). While busy, the icon
/// plays exactly one full rotation as feedback that a refresh started.
///
/// The spin is a single fixed-duration animation, not tied to how long the
/// actual fetch takes — most refreshes finish well under a second, so
/// animating continuously until `isBusy` goes false (via `TimelineView` or
/// `repeatForever`) gets cut off mid-turn far more often than not, which
/// reads as a stutter rather than a spin. Firing one clean 360° turn on
/// the rising edge of `isBusy` always completes, and a one-shot animation
/// has no repeating object that can leak or stack on a second tap — the
/// bug class that made the previous approach stick.
struct RoundIconButton: View {
    let systemName: String
    var isBusy = false
    let action: () -> Void
    @State private var rotation = 0.0

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.ink)
                .rotationEffect(.degrees(rotation))
                .frame(width: 40, height: 40)
                .background(Theme.card, in: Circle())
                .shadow(color: Theme.shadowSoft, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onChange(of: isBusy) { wasBusy, busy in
            guard busy, !wasBusy else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                rotation += 360
            }
        }
    }
}
