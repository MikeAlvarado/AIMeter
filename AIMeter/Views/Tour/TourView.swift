import SwiftUI
import UsageKit

/// The full tour (see `Tour`): one step at a time, its animation on top,
/// what it is, and a button that turns it on; "Not now" moves on without
/// it, "Skip tour" leaves. A step already on says so and only continues,
/// and one that can't show here is passed over (`TourActions.applies`).
/// The last step connects an account. `finish` closes the tour, true when
/// the user asked to connect (the Connect sheet opens once it is gone).
struct TourView: View {
    var steps = Tour.steps
    /// Above "Skip tour": less on the Mac, whose window has no title bar
    /// and puts it beside its own buttons.
    var topPadding: CGFloat = 28
    let finish: (_ connect: Bool) -> Void
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif
    /// The step on screen; nil until the first one is left.
    @State private var current: TourFeature?
    @State private var notificationsAllowed = false
    @State private var working = false
    /// Bumped after an action, and whenever the app comes back to the
    /// front (from a system prompt or System Settings), so what is on is
    /// read again.
    @State private var revision = 0

    /// The steps that show here, as the dots count them.
    private var shown: [TourFeature] {
        steps.filter { TourActions.applies($0, prefs: prefs) }
    }

    private var feature: TourFeature { current ?? shown.first ?? .welcome }

    var body: some View {
        let feature = feature
        let shown = shown
        VStack(spacing: 22) {
            HStack {
                Spacer()
                Button(String(localized: "Skip tour")) { finish(false) }
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            // The step floats between "Skip tour" and the buttons, which
            // keep to the bottom, so they stay put from one step to the next.
            Spacer(minLength: 0)
            TourVisual(feature: feature)
                .id(feature)
                .transition(.opacity)
            VStack(spacing: 8) {
                Text(TourText.title(feature))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text(TourText.detail(feature))
                    .font(.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(feature)
            Spacer(minLength: 0)
            buttons(for: feature, last: next(after: feature) == nil)
            PageDots(count: shown.count, index: shown.firstIndex(of: feature) ?? 0)
        }
        .padding([.horizontal, .bottom], 28)
        .padding(.top, topPadding)
        .frame(maxWidth: 460)
        .task(id: revision) {
            notificationsAllowed = await TourActions.notificationsAuthorized()
            #if os(macOS)
            ClaudeSessionMonitor.shared.refreshHooksState()
            #endif
        }
        #if os(macOS)
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                revision += 1
            }
        }
        #else
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { revision += 1 }
        }
        #endif
    }

    @ViewBuilder
    private func buttons(for feature: TourFeature, last: Bool) -> some View {
        let _ = revision
        let active = TourActions.isActive(feature, model: model, prefs: prefs, notificationsAllowed: notificationsAllowed)
        VStack(spacing: 10) {
            if let action = TourActions.title(for: feature), !active {
                CapsuleActionButton(title: action) { act(on: feature) }
                    .disabled(working)
                    .keyboardShortcut(.defaultAction)
                CapsuleActionButton(title: last ? String(localized: "Later") : String(localized: "Not now"), prominent: false) {
                    advance()
                }
            } else {
                if active {
                    TourActiveLabel(feature: feature)
                }
                CapsuleActionButton(title: last ? String(localized: "Done") : String(localized: "Continue")) {
                    advance()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func act(on feature: TourFeature) {
        // An account is connected in the Connect sheet, once the tour is
        // closed: nothing is presented over it.
        guard feature != .connect else {
            finish(true)
            return
        }
        Task {
            working = true
            await TourActions.perform(feature, model: model, prefs: prefs)
            working = false
            revision += 1
        }
    }

    /// The step after `feature` that shows here; nil after the last.
    private func next(after feature: TourFeature) -> TourFeature? {
        guard let index = steps.firstIndex(of: feature) else { return nil }
        return steps[(index + 1)...].first { TourActions.applies($0, prefs: prefs) }
    }

    private func advance() {
        guard let next = next(after: feature) else {
            finish(false)
            return
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            current = next
        }
    }
}

/// "On" once a step's feature is, or "Connected"; a login item macOS
/// still has to approve says so, with the way to the pane.
struct TourActiveLabel: View {
    let feature: TourFeature
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 6) {
            Label(TourActions.activeLabel(for: feature), systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.accent)
            #if os(macOS)
            if feature == .openAtLogin, LoginItemManager().needsApproval {
                HStack(spacing: 8) {
                    Text("Waiting for approval in System Settings.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    Button(String(localized: "Open Settings")) {
                        if let url = LoginItemManager.settingsURL { openURL(url) }
                    }
                    .buttonStyle(.plain)
                    .font(Theme.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }
            }
            #endif
        }
    }
}

/// Where the tour stands, as dots.
private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { dot in
                Circle()
                    .fill(dot == index ? Theme.accent : Theme.track)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Step \(index + 1) of \(count)"))
    }
}

/// A new feature's card inside a release's notes: its animation and,
/// while it is off, the button that turns it on (the tour's own action),
/// or "On" once it is. Only the animation where the feature can't show
/// here (`TourActions.applies`) or has no switch.
struct TourFeatureCard: View {
    let feature: TourFeature
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @State private var notificationsAllowed = false
    @State private var working = false
    @State private var revision = 0

    var body: some View {
        VStack(spacing: 10) {
            TourVisual(feature: feature, height: 140)
            let _ = revision
            if let action = TourActions.title(for: feature), TourActions.applies(feature, prefs: prefs) {
                if TourActions.isActive(feature, model: model, prefs: prefs, notificationsAllowed: notificationsAllowed) {
                    TourActiveLabel(feature: feature)
                } else {
                    CapsuleActionButton(title: action) {
                        Task {
                            working = true
                            await TourActions.perform(feature, model: model, prefs: prefs)
                            working = false
                            revision += 1
                        }
                    }
                    .disabled(working)
                }
            }
        }
        .task(id: revision) {
            notificationsAllowed = await TourActions.notificationsAuthorized()
            #if os(macOS)
            ClaudeSessionMonitor.shared.refreshHooksState()
            #endif
        }
        #if os(macOS)
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                revision += 1
            }
        }
        #endif
    }
}
