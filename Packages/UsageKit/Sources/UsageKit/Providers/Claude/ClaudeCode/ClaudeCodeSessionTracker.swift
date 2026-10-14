import Foundation

/// The rules, pure: log records and hook events in, sessions out. A turn
/// starts with a prompt or any tool traffic and ends with a reply that
/// ends it, the stop summary Claude Code writes after it, an interruption
/// or an API error. A subagent's records (a sidechain, or a file under
/// `<session>/subagents/`) only ever mean the parent is working. Only the
/// hooks can tell that a session waits for a permission prompt; the log
/// says when it was answered (the agent that asked writes again).
public struct ClaudeCodeSessionTracker: Sendable {
    public private(set) var sessions: [String: ClaudeCodeSessionActivity] = [:]

    public init() {}

    /// Applies one record from the log of `fileSessionID`, written by the
    /// subagent `agentID` (its file's id) or, when nil, the session itself.
    public mutating func apply(_ record: ClaudeCodeSessionRecord, fileSessionID id: String, agentID: String? = nil, now: Date) {
        let time = record.timestamp ?? now
        // A session first met through a record that says nothing about its
        // state (a title) is known, not shown: it has no activity yet.
        var session = sessions[id] ?? Self.unseen(id)
        if let title = record.customTitle { session.customTitle = title }
        if let title = record.aiTitle { session.aiTitle = title }
        let agent = record.agentId ?? agentID ?? ""
        // A subagent may work in a worktree: the session's own folder names it.
        if agent.isEmpty, let cwd = record.cwd, !cwd.isEmpty {
            session.project = (cwd as NSString).lastPathComponent
        }
        let effect = Self.effect(of: record, sidechain: !agent.isEmpty || record.isSidechain == true)
        if effect != .none {
            session.lastActivity = max(session.lastActivity, time)
            // The agent whose prompt was open went on after it: answered,
            // or declined.
            if let asked = session.permissionRequests[agent], time > asked {
                session.permissionRequests[agent] = nil
                if session.permissionRequests.isEmpty, case .needsPermission = session.state {
                    session.work(at: max(time, session.stateTime))
                }
            }
            if time >= session.stateTime {
                switch effect {
                case .work where session.permissionRequests.isEmpty: session.work(at: time)
                case .finish: session.finish(at: time)
                default: break
                }
            }
        }
        sessions[id] = session
    }

    private static func unseen(_ id: String) -> ClaudeCodeSessionActivity {
        ClaudeCodeSessionActivity(id: id, state: .finished(at: .distantPast), lastActivity: .distantPast)
    }

    /// Applies one hook event: a prompt means working, a permission
    /// request waiting for the user, a stop (or, as a fallback, the idle
    /// notification) finished, and the session's end removes it.
    public mutating func apply(_ event: ClaudeCodeHookEvent, now: Date) {
        let id = event.sessionId
        if event.hookEventName == "SessionEnd" {
            sessions[id] = nil
            return
        }
        var session = sessions[id] ?? Self.unseen(id)
        if event.agentId == nil, session.project == nil, let cwd = event.cwd, !cwd.isEmpty {
            session.project = (cwd as NSString).lastPathComponent
        }
        switch event.hookEventName {
        case "UserPromptSubmit":
            session.permissionRequests = [:]
            session.work(at: now)
        case "PermissionRequest":
            session.askPermission(of: event.agentId ?? "", at: now)
        case "Notification" where event.notificationType == "idle_prompt":
            if session.isActive { session.finish(at: now) }
        case "Stop", "StopFailure":
            session.finish(at: now)
        default:
            break
        }
        session.lastActivity = max(session.lastActivity, now)
        sessions[id] = session
    }

    /// What to show at `now`: sessions working or waiting (unless silent
    /// for `staleAfter`, which only a crash or a closed app leaves behind,
    /// since a working session writes as it goes), then those that
    /// finished within `finishedFor`. The active ones by the start of
    /// their turn and the finished ones by when, newest first, so a row
    /// moves only when its session starts a turn or ends one.
    public func visible(now: Date, finishedFor: TimeInterval = 600, staleAfter: TimeInterval = 1800) -> [ClaudeCodeSessionActivity] {
        let active = sessions.values
            .filter { $0.isActive && now.timeIntervalSince($0.lastActivity) < staleAfter }
            .sorted { ($0.workingSince ?? .distantPast, $0.id) > ($1.workingSince ?? .distantPast, $1.id) }
        let finished = sessions.values
            .filter { session in
                guard let at = session.finishedAt else { return false }
                return now.timeIntervalSince(at) < finishedFor
            }
            .sorted { ($0.finishedAt ?? .distantPast, $0.id) > ($1.finishedAt ?? .distantPast, $1.id) }
        return active + finished
    }

    /// Forgets the sessions not heard from in `age`, so a Mac that runs
    /// for weeks doesn't keep every session it ever saw.
    public mutating func prune(now: Date, olderThan age: TimeInterval = 86_400) {
        sessions = sessions.filter { now.timeIntervalSince($0.value.lastActivity) < age }
    }

    enum Effect { case work, finish, none }

    static func effect(of record: ClaudeCodeSessionRecord, sidechain: Bool) -> Effect {
        switch record.type {
        case "user":
            if record.isMeta == true { return .none }
            if !sidechain, record.isInterruption { return .finish }
            return .work
        case "assistant":
            if sidechain { return .work }
            if record.isApiErrorMessage == true { return .finish }
            switch record.message?.stopReason {
            case "end_turn", "stop_sequence", "max_tokens", "refusal": return .finish
            default: return .work
            }
        case "system":
            if sidechain { return .work }
            switch record.subtype {
            case "stop_hook_summary", "turn_duration": return .finish
            case "compact_boundary", "api_error": return .work
            default: return .none
            }
        default:
            return .none
        }
    }
}

extension ClaudeCodeSessionActivity {
    var workingSince: Date? {
        switch state {
        case .working(let since), .needsPermission(let since): since
        case .finished: nil
        }
    }

    var finishedAt: Date? {
        if case .finished(let at) = state, at != .distantPast { at } else { nil }
    }

    /// Working from `time` on; a turn under way keeps its start.
    mutating func work(at time: Date) {
        state = .working(since: workingSince ?? time)
        stateTime = max(stateTime, time)
    }

    /// Waiting for the permission prompt `agent` opened at `time`.
    mutating func askPermission(of agent: String, at time: Date) {
        permissionRequests[agent] = permissionRequests[agent] ?? time
        state = .needsPermission(since: workingSince ?? time)
        stateTime = max(stateTime, time)
    }

    /// Finished at `time`. A turn's later end records (the reply, then
    /// the stop summary) keep the first one's time.
    mutating func finish(at time: Date) {
        permissionRequests = [:]
        if finishedAt == nil { state = .finished(at: time) }
        stateTime = max(stateTime, time)
    }
}
