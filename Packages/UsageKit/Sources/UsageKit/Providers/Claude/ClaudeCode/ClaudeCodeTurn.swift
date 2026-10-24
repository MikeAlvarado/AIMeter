import Foundation

/// What a session's turn has done so far, for the notch island: its steps
/// (each a kind of action, from the names of the tools the replies call,
/// never what they were given), how many edits, and, when the desktop
/// app keeps a plan for it, which of the plan's steps it is on. Built by
/// `ClaudeCodeSessionTracker` from the session's own thread; a subagent's
/// work is the "Delegating" step that started it.
public struct ClaudeCodeTurn: Sendable {
    public typealias PlanStatus = ClaudeCodeSessionRecord.ToolUse.PlanStatus

    /// A step's kind of action. Consecutive tools of one kind are one step.
    public enum Action: String, Equatable, Sendable, CaseIterable {
        case thinking, reading, editing, running, searching, web, delegating, browsing, tool

        /// The action a tool is, by its name; nil for the bookkeeping
        /// tools (the plan, the desktop app's turn tools), which aren't a
        /// step of the work.
        public init?(tool name: String) {
            if name.hasPrefix(ClaudeCodeTurn.bookkeepingPrefix) { return nil }
            switch name {
            case "Read", "NotebookRead": self = .reading
            case "Edit", "MultiEdit", "Write", "NotebookEdit": self = .editing
            case "Bash", "BashOutput", "KillShell", "KillBash": self = .running
            case "Grep", "Glob", "LS", "ToolSearch": self = .searching
            case "WebFetch", "WebSearch": self = .web
            case "Agent", "Task", "SendMessage": self = .delegating
            default:
                if name.hasPrefix("mcp__Claude_Browser__") || name.hasPrefix("mcp__claude-in-chrome__") {
                    self = .browsing
                } else {
                    self = .tool
                }
            }
        }

        /// Whether a tool of this name changes a file.
        static func isEdit(_ name: String) -> Bool {
            ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(name)
        }
    }

    public struct Step: Equatable, Sendable {
        public let action: Action
        public let start: Date
        /// The tools of this kind called in a row.
        public var count: Int

        public init(action: Action, start: Date, count: Int = 1) {
            self.action = action
            self.start = start
            self.count = count
        }
    }

    /// The desktop app's plan tool, and the prefix of its turn tools.
    public static let planTool = "mcp__ccd_turn__update_plan"
    static let bookkeepingPrefix = "mcp__ccd_turn__"
    /// The steps kept, the newest: more than any view shows.
    static let keptSteps = 12

    public let start: Date
    /// The newest steps, oldest first, at most `keptSteps`.
    public private(set) var steps: [Step] = []
    /// Every step the turn has taken, those no longer kept included.
    public private(set) var stepCount = 0
    /// Tools that changed a file, each call once.
    public private(set) var edits = 0
    /// The plan's steps, when the desktop app keeps one this turn.
    public private(set) var plan: [PlanStatus]?
    private var seenTools: Set<String> = []

    public init(start: Date) {
        self.start = start
    }

    /// A turn as given: the demo's.
    public init(start: Date, steps: [Step], edits: Int = 0, plan: [PlanStatus]? = nil) {
        self.start = start
        self.steps = Array(steps.suffix(Self.keptSteps))
        stepCount = steps.count
        self.edits = edits
        self.plan = plan
    }

    /// The step under way, the newest.
    public var current: Step? { steps.last }

    /// Which of the plan's steps is under way, from 1, and how many there
    /// are; past the last, every one is done.
    public var planPosition: (step: Int, of: Int)? {
        guard let plan, !plan.isEmpty else { return nil }
        if let index = plan.firstIndex(of: .inProgress) { return (index + 1, plan.count) }
        let done = plan.filter { $0 == .completed }.count
        return (min(done + 1, plan.count), plan.count)
    }

    /// Adds what a reply at `time` calls. A tool seen before (the same
    /// reply written again) counts once.
    mutating func apply(_ tools: [ClaudeCodeSessionRecord.ToolUse], thinks: Bool, at time: Date) {
        if thinks, steps.isEmpty, tools.isEmpty {
            append(.thinking, at: time)
        }
        for tool in tools where seenTools.insert(tool.id.isEmpty ? UUID().uuidString : tool.id).inserted {
            if let update = tool.plan { applyPlan(update) }
            guard let action = Action(tool: tool.name) else { continue }
            if Action.isEdit(tool.name) { edits += 1 }
            append(action, at: time)
        }
    }

    private mutating func append(_ action: Action, at time: Date) {
        if let last = steps.last, last.action == action {
            steps[steps.count - 1].count += 1
            return
        }
        steps.append(Step(action: action, start: max(time, steps.last?.start ?? time), count: 1))
        stepCount += 1
        if steps.count > Self.keptSteps { steps.removeFirst(steps.count - Self.keptSteps) }
    }

    private mutating func applyPlan(_ update: ClaudeCodeSessionRecord.ToolUse.PlanUpdate) {
        switch update {
        case .set(let statuses):
            plan = statuses
        case .advance:
            guard var plan else { return }
            if let index = plan.firstIndex(of: .inProgress) {
                plan[index] = .completed
                if let next = plan[index...].firstIndex(of: .pending) { plan[next] = .inProgress }
            } else if let next = plan.firstIndex(of: .pending) {
                plan[next] = .inProgress
            }
            self.plan = plan
        case .mark(let done, let start):
            guard var plan else { return }
            for number in done where plan.indices.contains(number - 1) {
                plan[number - 1] = .completed
            }
            if let start, plan.indices.contains(start - 1) {
                for index in plan.indices where plan[index] == .inProgress { plan[index] = .pending }
                plan[start - 1] = .inProgress
            }
            self.plan = plan
        }
    }
}

extension ClaudeCodeTurn: Equatable {
    /// Equal when they show the same thing; which tool ids were counted
    /// is bookkeeping.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.start == rhs.start && lhs.steps == rhs.steps && lhs.stepCount == rhs.stepCount
            && lhs.edits == rhs.edits && lhs.plan == rhs.plan
    }
}
