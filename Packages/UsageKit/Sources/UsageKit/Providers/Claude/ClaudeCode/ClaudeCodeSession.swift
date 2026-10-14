import Foundation

/// What one Claude Code session is doing, for the notch island: working
/// (since when), waiting for the user's permission (only the hooks can
/// tell), or finished (when). Every Claude Code client on the Mac writes
/// its sessions to the same `~/.claude/projects` (the desktop app, a
/// second copy of it, the CLI), so one watcher sees them all.
public struct ClaudeCodeSessionActivity: Sendable, Identifiable {
    /// `since` is when the turn started, waiting for permission included.
    public enum State: Equatable, Sendable {
        case working(since: Date)
        case needsPermission(since: Date)
        case finished(at: Date)
    }

    /// The session's id (its log file's name).
    public let id: String
    /// The titles Claude keeps for the sidebar: the one the user gave it,
    /// and the one Claude generated.
    public var customTitle: String?
    public var aiTitle: String?
    /// The folder the session works in, its last component.
    public var project: String?
    public var state: State
    /// The newest record or hook event seen for it.
    public var lastActivity: Date
    /// The time of the newest record or event that decided `state`. An
    /// older record, read late (one file of a session read after another,
    /// or the log catching up with a hook), never overrides it.
    var stateTime: Date
    /// The permission prompts still open, by agent ("" for the session's
    /// own thread), with when each was asked.
    var permissionRequests: [String: Date] = [:]

    public init(id: String, customTitle: String? = nil, aiTitle: String? = nil, project: String? = nil, state: State, lastActivity: Date) {
        self.id = id
        self.customTitle = customTitle
        self.aiTitle = aiTitle
        self.project = project
        self.state = state
        self.lastActivity = lastActivity
        stateTime = lastActivity
    }

    /// The title Claude shows in its sidebar, when the log has one yet.
    public var title: String? { customTitle ?? aiTitle }

    /// The name to show: the title, else the project, else a short id.
    public var name: String {
        title ?? project ?? String(id.prefix(8))
    }

    public var isActive: Bool {
        if case .finished = state { false } else { true }
    }
}

extension ClaudeCodeSessionActivity: Equatable {
    /// Equal when they show the same thing. The bookkeeping (when it was
    /// last heard from, which prompts are open) is left out, so a session
    /// writing its log doesn't republish an unchanged list.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.customTitle == rhs.customTitle && lhs.aiTitle == rhs.aiTitle
            && lhs.project == rhs.project && lhs.state == rhs.state
    }
}

/// One line of a session log reduced to what says whether the session is
/// working: the record's type and time, ids, the message's stop reason and
/// the *types* of its content items, and the title records. The
/// `Decodable` declares nothing else, so no prompt, reply or tool input is
/// ever decoded, by construction (the same rule as the usage reader's).
public struct ClaudeCodeSessionRecord: Decodable, Equatable, Sendable {
    public let type: String?
    public let subtype: String?
    public let timestamp: Date?
    public let sessionId: String?
    /// The subagent a record belongs to (every record of a
    /// `subagents/…/agent-<id>.jsonl`), nil on the session's own thread.
    public let agentId: String?
    public let isSidechain: Bool?
    public let isMeta: Bool?
    public let isApiErrorMessage: Bool?
    public let cwd: String?
    /// Set on the record that marks an interrupted turn.
    public let interruptedMessageId: String?
    public let customTitle: String?
    public let aiTitle: String?
    public let message: Message?
    /// On every prompt (typed, queued, sent by the app or the system) and
    /// never on the interruption marker. Only its presence is read.
    let promptSource: Presence?

    public struct Message: Decodable, Equatable, Sendable {
        public let stopReason: String?
        /// "text", "tool_use", "tool_result", "thinking", "image"…; a
        /// plain-string content (a typed prompt) counts as one "text".
        public let contentKinds: [String]
        /// The content is a plain string, the way a typed prompt is stored.
        public let isPlainText: Bool

        enum CodingKeys: String, CodingKey {
            case stopReason = "stop_reason", content
        }

        private struct Item: Decodable {
            let type: String?
        }

        public init(stopReason: String?, contentKinds: [String], isPlainText: Bool = false) {
            self.stopReason = stopReason
            self.contentKinds = contentKinds
            self.isPlainText = isPlainText
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)
            if let items = try? container.decodeIfPresent([Item].self, forKey: .content) {
                contentKinds = items.compactMap(\.type)
                isPlainText = false
            } else {
                isPlainText = container.contains(.content)
                contentKinds = isPlainText ? ["text"] : []
            }
        }
    }

    /// A key's presence, whatever its value: decoding it reads nothing.
    struct Presence: Decodable, Equatable, Sendable {
        init() {}
        init(from decoder: Decoder) throws {}
    }

    public init(
        type: String?, subtype: String? = nil, timestamp: Date?, sessionId: String?, agentId: String? = nil,
        isSidechain: Bool? = nil, isMeta: Bool? = nil, isApiErrorMessage: Bool? = nil, cwd: String? = nil,
        interruptedMessageId: String? = nil, customTitle: String? = nil, aiTitle: String? = nil,
        message: Message? = nil, isPrompt: Bool = false
    ) {
        self.type = type
        self.subtype = subtype
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.agentId = agentId
        self.isSidechain = isSidechain
        self.isMeta = isMeta
        self.isApiErrorMessage = isApiErrorMessage
        self.cwd = cwd
        self.interruptedMessageId = interruptedMessageId
        self.customTitle = customTitle
        self.aiTitle = aiTitle
        self.message = message
        promptSource = isPrompt ? Presence() : nil
    }

    /// Whether the record ends a turn of the session's own thread: how far
    /// back a log seen for the first time is read, so a session already at
    /// work counts its time from the prompt after it, the turn's real
    /// start. (Not a prompt: one sent while a turn runs joins that turn.)
    public var endsTurn: Bool {
        guard agentId == nil, isSidechain != true else { return false }
        return ClaudeCodeSessionTracker.effect(of: self, sidechain: false) == .finish
    }

    /// The marker Claude Code writes when the user stops a turn, during a
    /// reply, a tool or a permission prompt: a user record of text alone,
    /// sent as a list rather than the plain string a typed prompt is, and
    /// without a prompt's source. Measured on 2026-10-14 over every log on
    /// this Mac: all 37 such records were that marker, and only one marker
    /// carried `interruptedMessageId`. Read from the record's shape; the
    /// text itself is never decoded.
    public var isInterruption: Bool {
        guard type == "user", isMeta != true, promptSource == nil else { return false }
        if interruptedMessageId != nil { return true }
        guard let message, !message.isPlainText, !message.contentKinds.isEmpty else { return false }
        return message.contentKinds.allSatisfy { $0 == "text" }
    }

    /// One JSONL line; nil for anything that isn't a record (a blank or
    /// partial line).
    public static func parse(_ line: Data) -> ClaudeCodeSessionRecord? {
        try? decoder.decode(ClaudeCodeSessionRecord.self, from: line)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = ClaudeCodeSessionRecord.date(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
            }
            return date
        }
        return decoder
    }()

    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// An event a Claude Code hook sends (`ClaudeCodeHooks`): the event's
/// name, the session and its folder, the subagent it came from, and for a
/// notification its kind. Nothing else is declared, so the prompt, a
/// tool's input or a reply never is.
public struct ClaudeCodeHookEvent: Decodable, Equatable, Sendable {
    public let hookEventName: String
    public let sessionId: String
    public let cwd: String?
    /// Set inside a subagent: whose permission prompt it is.
    public let agentId: String?
    public let notificationType: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name", sessionId = "session_id", cwd
        case agentId = "agent_id", notificationType = "notification_type"
    }

    public init(hookEventName: String, sessionId: String, cwd: String? = nil, agentId: String? = nil, notificationType: String? = nil) {
        self.hookEventName = hookEventName
        self.sessionId = sessionId
        self.cwd = cwd
        self.agentId = agentId
        self.notificationType = notificationType
    }
}
