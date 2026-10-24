#if os(macOS)
import SwiftUI
import UsageKit

/// The session in the sneak, opened up in the expanded island and set
/// apart from the rows like a spotlight (a lit panel, its edge in the
/// accent, flashing when the user clicks another session into it): its name, how long its turn has run, what it is
/// doing right now in large type, six segments, the steps before it and a
/// footer with what the user can do (see "Claude Code sessions" in the
/// repo-root CLAUDE.md). Every part keeps one size whatever it holds, so
/// nothing in the island moves as a step is added: the window holds three
/// steps, the new one rolls in at the bottom and the oldest leaves at the
/// top, and the footer is one height for a line or for buttons. In demo
/// mode its buttons act on the demo's sessions (`DemoSessions`).
struct SessionCard: View {
    let row: NotchIslandModel.Sessions.Row
    let turn: NotchIslandModel.Sessions.Turn
    var showsPet = true
    @Environment(\.notchIslandActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PreferencesModel.self) private var prefs
    @Environment(UsageModel.self) private var model
    private var monitor: ClaudeSessionMonitor { .shared }

    /// When the card last changed what it shows (the session, its state,
    /// the prompt it waits on): its buttons ignore a click for
    /// `settleTime` after that, so a click aimed at what was there a
    /// moment ago never acts on what replaced it.
    @State private var changedAt = Date()
    static let settleTime: TimeInterval = 0.6
    /// 1 the moment the card takes a session, easing to 0: its edge flashes.
    @State private var flash: CGFloat = 0
    private var demo: DemoSessions { .shared }

    static let stepHeight: CGFloat = 20
    static let stepSpacing: CGFloat = 6
    static let footerHeight: CGFloat = 26

    /// The prompt the island can answer for this session (the demo's own
    /// in demo mode).
    private var ask: ClaudeCodePermissionAsk? {
        guard row.status == .waiting else { return nil }
        return model.isDemoMode ? demo.asks[row.id] : monitor.asks[row.id]?.request
    }

    /// The buttons that answer Claude Code: with "Answer from the island"
    /// on, or on the demo's sessions.
    private var answers: Bool { model.isDemoMode || (monitor.hooksAnswer && prefs.claudeSessionsAnswers) }

    /// The card's one color, the accent, whatever the session does: no
    /// yellow on the card or its controls (Mike's call, 2026-10-24: a
    /// sober app).
    private var spot: Color { Theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            nowLine
            SegmentStrip(segments: turn.segments)
            steps
            footer
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07 + 0.05 * flash)))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(spot.opacity(0.5 + 0.5 * flash), lineWidth: 1 + 1.5 * flash)
        }
        .onChange(of: shownState) { _, _ in changedAt = Date() }
        // A new session in the card is a new card (`.id` in the section),
        // so appearing is taking a session.
        .onAppear { spotlight() }
    }

    /// The edge flashes and settles, so the session just put here stands out.
    private func spotlight() {
        guard !reduceMotion else { return }
        flash = 1
        withAnimation(.easeOut(duration: 1.1)) { flash = 0 }
    }

    /// What the buttons act on: the session, whether it waits, on what.
    private var shownState: [String] {
        [row.id, "\(row.status)", model.isDemoMode ? "" : monitor.asks[row.id].map { "\($0.ticket)" } ?? ""]
    }

    // MARK: Now

    /// What the session is doing right now, the card's headline: the step
    /// under way and how long it has been at it, what it asks permission
    /// for, or how the turn ended. Two lines, always.
    private var nowLine: some View {
        // A new state is a new line: the old fades out before the new
        // fades in, never drawn over it.
        ZStack(alignment: .leading) {
            nowContent
                .id("\(row.status)·\(nowTitle)")
                .transition(.notchSwap)
        }
        .animation(.smooth(duration: 0.3), value: "\(row.status)·\(nowTitle)")
    }

    private var nowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: nowSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(spot)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(nowTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .modifier(Shimmer(active: row.status == .working && current != nil))
                nowDetail
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(NotchIslandStyle.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .accessibilityElement(children: .combine)
    }

    /// The step under way.
    private var current: NotchIslandModel.Sessions.Turn.Step? {
        guard let last = turn.steps.last, last.duration == nil else { return nil }
        return last
    }

    private var nowSymbol: String {
        switch row.status {
        case .waiting: "exclamationmark.triangle.fill"
        case .finished: "checkmark.circle.fill"
        case .working: current?.symbol ?? "sparkle"
        }
    }

    private var nowTitle: String {
        switch row.status {
        case .waiting: String(localized: "Needs permission")
        case .finished: String(localized: "Finished")
        case .working: current?.label ?? String(localized: "Thinking")
        }
    }

    @ViewBuilder
    private var nowDetail: some View {
        switch row.status {
        case .waiting:
            Text(ask.map(Self.describe) ?? String(localized: "Answer in Claude"))
        case .finished:
            Text(turn.summary ?? "")
        case .working:
            if let current {
                HStack(spacing: 4) {
                    Text("On this step for")
                    Text(current.id, style: .timer)
                }
            } else {
                Text(turn.start, style: .timer)
            }
        }
    }

    /// Runs `action` unless the card changed a moment ago.
    private func settled(_ action: @escaping () -> Void) -> () -> Void {
        { if Date().timeIntervalSince(changedAt) >= Self.settleTime { action() } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            SessionRowView(row: row, showsPet: showsPet, showsDetail: false)
            if !turn.isFinished {
                Text(turn.start, style: .timer)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(NotchIslandStyle.reset)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: Self.stepSpacing) {
            // What it already did; the headline says what it does now.
            ForEach(turn.history) { step in
                StepLine(step: step)
                    .frame(height: Self.stepHeight)
                    .transition(stepTransition)
            }
        }
        .frame(height: Self.stepHeight * CGFloat(NotchIslandModel.Sessions.Turn.shownSteps)
            + Self.stepSpacing * CGFloat(NotchIslandModel.Sessions.Turn.shownSteps - 1), alignment: .top)
        .clipped()
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: turn.history.map(\.id))
    }

    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    /// "Bash: git push origin main", or the tool alone.
    nonisolated static func describe(_ request: ClaudeCodePermissionAsk) -> String {
        guard let subject = request.subject else { return request.toolName }
        return "\(request.toolName): \(subject)"
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                HStack(spacing: 8) { footerLead }
                    .id(footerMode)
                    .transition(.notchSwap)
            }
            .animation(.smooth(duration: 0.3), value: footerMode)
            Spacer(minLength: 8)
            if !model.isDemoMode, let app = monitor.openTargets[row.id], let actions {
                IslandTextButton(title: String(localized: "Open in \(app)"), symbol: "arrow.up.right") {
                    monitor.open(row.id)
                    actions.close()
                }
            }
        }
        .frame(height: Self.footerHeight)
    }

    /// What the footer holds, for its swap: the end, the prompt's buttons,
    /// or Stop and the progress.
    private var footerMode: String {
        if turn.isFinished { return "finished" }
        return ask != nil && answers ? "ask" : "working"
    }

    @ViewBuilder
    private var footerLead: some View {
        if turn.isFinished {
            if let progress = turn.progress {
                Text(progress)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(NotchIslandStyle.reset)
                    .lineLimit(1)
            }
        } else if ask != nil, answers, actions != nil {
            let id = row.id
            let demoMode = model.isDemoMode
            IslandPillButton(title: String(localized: "Approve"), symbol: "checkmark", prominent: true,
                             action: settled { demoMode ? demo.approve(id) : monitor.approve(id) })
            IslandPillButton(title: String(localized: "Deny"), symbol: "xmark",
                             action: settled { demoMode ? demo.deny(id) : monitor.deny(id) })
        } else {
            if answers, actions != nil, row.status == .working {
                let id = row.id
                let demoMode = model.isDemoMode
                let stopping = !demoMode && monitor.stopping.contains(id)
                IslandPillButton(title: stopping ? String(localized: "Stopping…") : String(localized: "Stop"), symbol: "stop.fill",
                                 action: settled { demoMode ? demo.stop(id) : monitor.stopSession(id) })
                    .disabled(stopping)
            }
            if let progress = turn.progress {
                Text(progress)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(NotchIslandStyle.reset)
                    .lineLimit(1)
            }
        }
    }
}

/// A step already done: its action's symbol, its name and how long it
/// took. The one under way is the card's headline, not a line here.
private struct StepLine: View {
    let step: NotchIslandModel.Sessions.Turn.Step

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: step.symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NotchIslandStyle.reset)
                .frame(width: 14)
            Text(step.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchIslandStyle.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(step.duration.map(NotchIslandModel.Sessions.Turn.duration) ?? "")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(NotchIslandStyle.reset)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Six segments: the steps done in the accent, the one under way at
/// half strength with a light passing over it again and again (there is
/// no knowing when a step ends), the rest a faint track.
private struct SegmentStrip: View {
    let segments: [NotchIslandModel.Sessions.Turn.Segment]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments.indices, id: \.self) { index in
                switch segments[index] {
                case .done: Capsule().fill(Theme.accent)
                case .now: Capsule().fill(Theme.accent.opacity(0.38)).overlay { Glint() }.clipShape(Capsule())
                case .empty: Capsule().fill(NotchIslandStyle.track)
                }
            }
        }
        .frame(height: 3)
        .animation(.smooth(duration: 0.3), value: segments)
        .accessibilityHidden(true)
    }
}

/// The light that passes over the segment under way, left to right, every
/// 2.2 s; nothing under Reduce Motion.
private struct Glint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 with the light just off the left end, 1 just past the right.
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.65
            LinearGradient(
                colors: [.white.opacity(0), Color(red: 1, green: 0.886, blue: 0.831).opacity(0.85), .white.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: width)
            .offset(x: -width + phase * (proxy.size.width + width))
        }
        .opacity(reduceMotion ? 0 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 2.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

/// A soft highlight passing over the text of the step under way.
private struct Shimmer: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if active, !reduceMotion {
            content
                .overlay {
                    GeometryReader { proxy in
                        let width = proxy.size.width * 0.5
                        LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: width)
                            .offset(x: -width + phase * (proxy.size.width + width))
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { phase = 1 }
                }
        } else {
            content
        }
    }
}

/// The footer's buttons: a small capsule, filled in the accent for the
/// one that goes ahead.
private struct IslandPillButton: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : NotchIslandStyle.control)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(prominent ? Theme.accent : Color.white.opacity(0.12)))
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }
}

/// "Open in Claude Work ↗": text in the accent, the whole label clickable.
private struct IslandTextButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
