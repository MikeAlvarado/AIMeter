import Foundation
import UsageKit

extension NotchIslandModel.Sessions {
    /// Which session the expanded island's card shows: the one pinned
    /// while it is still listed with a turn, else the lead's. Pinned, it
    /// stays put however the lead changes, so a button is never pressed on
    /// a session other than the one shown.
    static func cardID(rows: [Row], lead: String?, pinned: String?) -> String? {
        if let pinned, rows.contains(where: { $0.id == pinned && $0.turn != nil }) { return pinned }
        if let lead, rows.contains(where: { $0.id == lead && $0.turn != nil }) { return lead }
        return nil
    }

    /// A session's turn as the expanded island's card shows it (see
    /// "Claude Code sessions" in the repo-root CLAUDE.md): the newest
    /// steps, each a kind of action and how long it took, a bar of six
    /// segments, how far along it is, and once it ended, how it went. Pure;
    /// the turn is UsageKit's `ClaudeCodeTurn`. Every piece keeps one size
    /// whatever it holds, so nothing in the island moves as a step is added.
    struct Turn: Equatable {
        struct Step: Equatable, Identifiable {
            let id: Date
            let action: ClaudeCodeTurn.Action
            let count: Int
            /// How long it took; nil for the step under way.
            let duration: TimeInterval?

            var label: String { Self.label(of: action) }

            /// "Reading · 3" for three in a row.
            var title: String { count > 1 ? "\(label) · \(count)" : label }

            static func label(of action: ClaudeCodeTurn.Action) -> String {
                switch action {
                case .thinking: String(localized: "Thinking")
                case .reading: String(localized: "Reading")
                case .editing: String(localized: "Editing")
                case .running: String(localized: "Running a command")
                case .searching: String(localized: "Searching")
                case .web: String(localized: "Searching the web")
                case .delegating: String(localized: "Working with an agent")
                case .browsing: String(localized: "Using the browser")
                case .tool: String(localized: "Using a tool")
                }
            }

            /// An SF Symbol for the action.
            var symbol: String {
                switch action {
                case .thinking: "sparkle"
                case .reading: "doc.text"
                case .editing: "pencil"
                case .running: "terminal"
                case .searching: "magnifyingglass"
                case .web: "globe"
                case .delegating: "person.2"
                case .browsing: "safari"
                case .tool: "wrench.and.screwdriver"
                }
            }
        }

        enum Segment: Equatable { case done, now, empty }

        let start: Date
        /// The newest steps, at most `shownSteps`, oldest first.
        let steps: [Step]
        /// The newest steps already done, at most `shownSteps`: what the
        /// card lists under its headline, which says the one under way.
        let history: [Step]
        let segments: [Segment]
        /// "4 steps", or "Step 3 of 7" with the desktop app's plan; nil
        /// before the first step.
        let progress: String?
        /// Once the turn ended: "Done in 13s · 6 edits".
        let summary: String?
        let isFinished: Bool

        static let shownSteps = 3
        static let segmentCount = 6

        init?(_ turn: ClaudeCodeTurn?, finishedAt: Date?, now: Date) {
            guard let turn else { return nil }
            start = turn.start
            isFinished = finishedAt != nil
            let kept = turn.steps
            let all = kept.indices.map { index in
                let step = kept[index]
                let end = index + 1 < kept.count ? kept[index + 1].start : finishedAt
                return Step(id: step.start, action: step.action, count: step.count, duration: end.map { max(0, $0.timeIntervalSince(step.start)) })
            }
            steps = Array(all.suffix(Self.shownSteps))
            history = Array(all.filter { $0.duration != nil }.suffix(Self.shownSteps))
            if let position = turn.planPosition {
                segments = Self.segments(total: position.of, current: position.step - 1, finished: isFinished)
                progress = String(localized: "Step \(position.step) of \(position.of)")
            } else {
                segments = Self.segments(total: nil, current: turn.stepCount - 1, finished: isFinished)
                progress = turn.stepCount > 0 ? String(localized: "\(turn.stepCount) steps") : nil
            }
            if let finishedAt {
                let took = Self.duration(finishedAt.timeIntervalSince(turn.start))
                let done = String(localized: "Done in \(took)")
                summary = turn.edits > 0 ? "\(done) · \(String(localized: "\(turn.edits) edits"))" : done
            } else {
                summary = nil
            }
        }

        /// Six segments over the steps: with a plan, one per plan step
        /// around the one under way; without, the newest steps, the one
        /// under way last. Done before it, nothing after.
        static func segments(total: Int?, current: Int, finished: Bool) -> [Segment] {
            let count = total ?? (current + 1)
            let first = total == nil
                ? max(0, current - (segmentCount - 1))
                : max(0, min(current - 2, count - segmentCount))
            return (0..<segmentCount).map { offset in
                let index = first + offset
                guard index < count else { return .empty }
                if finished { return .done }
                if index < current { return .done }
                return index == current ? .now : .empty
            }
        }

        /// "13s", "1m 12s", "1h 4m".
        nonisolated static func duration(_ seconds: TimeInterval) -> String {
            Duration.seconds(max(0, seconds.rounded())).formatted(
                .units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2)
            )
        }
    }
}
