#if os(macOS)
import AppKit
import Observation
import UsageKit
import UserNotifications

/// The Claude Code sessions the notch island shows (see "Claude Code
/// sessions" in the repo-root CLAUDE.md): which are working, which wait
/// for the user's permission, which just finished. Fed by the session
/// logs (`ClaudeSessionLogWatcher`, always) and, once the user installs
/// them, by Claude Code's own hooks (`ClaudeHookListener`), which add the
/// permission wait and report a turn's start and end the moment they
/// happen. Runs while the island shows sessions or the "needs you"
/// notification is on (`AppChrome.updateClaudeSessions`); the rules
/// themselves are UsageKit's `ClaudeCodeSessionTracker`.
@MainActor
@Observable
final class ClaudeSessionMonitor {
    static let shared = ClaudeSessionMonitor()

    /// What the island shows: working and waiting sessions, then the ones
    /// that finished in the last few minutes. Republished only when
    /// something shown changes, not on every line a session writes.
    private(set) var sessions: [ClaudeCodeSessionActivity] = []
    /// A session finished a moment ago: the collapsed island marks it for
    /// `finishedMarkDuration`.
    private(set) var justFinished: ClaudeCodeSessionActivity?
    /// When each session waiting for permission asked: one that asks after
    /// the user put another session in the island's sneak still takes it
    /// (`NotchIslandModel.Sessions.ordered`). Gone once it is answered.
    private(set) var askedAt: [String: Date] = [:]
    private(set) var isRunning = false
    /// Whether AIMeter's hooks are in Claude Code's settings, read when the
    /// monitor starts and after every install or removal.
    private(set) var hooksInstalled = false
    /// Whether they are in the answering mode ("Answer from the island").
    private(set) var hooksAnswer = false
    /// The permission prompts the island can answer, by session: what the
    /// tool would do, held while the prompt is open and never kept. Set
    /// only by `ClaudeSessionMonitor+Answers.swift` (internal, not
    /// private(set), for that file).
    var asks: [String: PermissionAsk] = [:]
    /// The sessions the user stopped from the island, until their turn ends.
    var stopping: Set<String> = []
    /// The sessions "Open" can bring up (`ClaudeSessionOpener`), with the
    /// name of the app each opens in ("Claude Work", "Terminal").
    var openTargets: [String: String] = [:]

    struct PermissionAsk: Equatable {
        let request: ClaudeCodePermissionAsk
        let ticket: ClaudeHookListener.Ticket
    }
    /// Why the last install or removal failed, shown under its button.
    private(set) var hooksError: String?

    // Internal rather than private where `ClaudeSessionMonitor+Answers.swift`
    // reads them.
    @ObservationIgnored var tracker = ClaudeCodeSessionTracker()
    @ObservationIgnored private var watcher: ClaudeSessionLogWatcher?
    @ObservationIgnored var listener: ClaudeHookListener?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var markTask: Task<Void, Never>?
    @ObservationIgnored private var notifiesWhenAsked = false
    @ObservationIgnored var answers = false
    /// The Claude Code process each session runs in, from its hooks.
    @ObservationIgnored var processes: [String: Int32] = [:]
    @ObservationIgnored let opener = ClaudeSessionOpener()

    static let finishedMarkDuration: Duration = .seconds(8)
    static let notificationPrefix = "claudesession."

    /// Whether this Mac has Claude Code's session logs at all.
    var logsExist: Bool {
        FileManager.default.fileExists(atPath: ClaudeSessionLogWatcher.defaultRoot.path)
    }

    // MARK: Lifecycle

    /// Starts or stops the watching; `notifies` is the "needs you"
    /// notification, `answers` "Answer from the island" (the hooks'
    /// answering mode).
    func update(enabled: Bool, notifies: Bool, answers: Bool = false) {
        notifiesWhenAsked = notifies
        if self.answers != answers {
            self.answers = answers
            if !answers { withdrawAsks() }
            if isRunning { refreshHooksState() }
        }
        // The unit-test host is this same app: a test run never watches
        // the tester's sessions or takes the hooks' socket.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if enabled { start() } else { stop() }
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        refreshHooksState()
        // What a previous run announced says nothing about now: a session
        // that asked then has been answered, or is no longer running.
        Task { await Self.withdrawDelivered { _ in true } }
        let watcher = ClaudeSessionLogWatcher { [weak self] batches in self?.apply(batches) }
        watcher.start()
        self.watcher = watcher
        let listener = ClaudeHookListener(
            deliver: { [weak self] event, pid in self?.apply(event, pid: pid) },
            ask: { [weak self] request, pid, ticket in self?.receive(request, pid: pid, ticket: ticket) }
        )
        listener.start()
        self.listener = listener
        // Ages finished sessions out, drops the silent ones, forgets old ones.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.tick()
            }
        }
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        watcher?.stop()
        watcher = nil
        listener?.stop()
        listener = nil
        ticker?.cancel()
        markTask?.cancel()
        tracker = ClaudeCodeSessionTracker()
        sessions = []
        justFinished = nil
        askedAt = [:]
        asks = [:]
        stopping = []
        processes = [:]
        openTargets = [:]
    }

    // MARK: Hooks

    /// Reads the hooks' state and brings AIMeter's entries to the mode
    /// asked for: answering installs them in that mode (the switch is the
    /// user's consent), and watching only rewrites entries already there
    /// (an older build's, or answering's after the switch went off).
    func refreshHooksState() {
        var state = ClaudeCodeHooks.state()
        let wanted: ClaudeCodeHooks.Mode = answers ? .answering : .watching
        if state.mode != wanted, answers || state.hasEntries {
            try? ClaudeCodeHooks.install(wanted)
            state = ClaudeCodeHooks.state()
        }
        if hooksInstalled != (state.mode != nil) { hooksInstalled = state.mode != nil }
        if hooksAnswer != (state.mode == .answering) { hooksAnswer = state.mode == .answering }
    }

    func installHooks() {
        changeHooks { try ClaudeCodeHooks.install(answers ? .answering : .watching) }
    }

    func removeHooks() {
        changeHooks(ClaudeCodeHooks.uninstall)
    }

    private func changeHooks(_ change: () throws -> Void) {
        do {
            try change()
            hooksError = nil
        } catch {
            hooksError = error.localizedDescription
        }
        refreshHooksState()
    }

    // MARK: Input

    private func apply(_ batches: [ClaudeSessionLogWatcher.Batch]) {
        let before = tracker.sessions
        let now = Date()
        for batch in batches {
            for record in batch.records {
                tracker.apply(record, fileSessionID: batch.sessionID, agentID: batch.agentID, now: now)
            }
        }
        settle(after: before, now: now)
    }

    func apply(_ event: ClaudeCodeHookEvent, pid: Int32?) {
        if let pid, event.hookEventName != "SessionEnd" { remember(pid, for: event.sessionId) }
        let before = tracker.sessions
        let now = Date()
        tracker.apply(event, now: now)
        settle(after: before, now: now)
    }

    /// Publishes the new list, marks a session that went from working to
    /// finished just now (a turn that had already ended when AIMeter first
    /// read its log is not news), and, when asked, announces a session that
    /// has just asked for permission and takes the notice back once it is
    /// answered or the session ends. A turn ending is never announced: the
    /// island shows it, and a notification for every turn was noise.
    private func settle(after before: [String: ClaudeCodeSessionActivity], now: Date) {
        for (id, session) in tracker.sessions {
            guard case .finished(let at) = session.state, now.timeIntervalSince(at) < 60,
                  let previous = before[id], previous.isActive else { continue }
            markFinished(session)
        }
        let asking = Self.newlyAsking(before: before, after: tracker.sessions)
        let noLonger = Self.noLongerAsking(before: before, after: tracker.sessions)
        if !asking.isEmpty || !noLonger.isEmpty {
            var times = askedAt
            asking.forEach { times[$0.id] = now }
            noLonger.forEach { times[$0] = nil }
            askedAt = times
        }
        if notifiesWhenAsked {
            asking.forEach(announce)
        }
        let answered = Set(noLonger.map { Self.notificationPrefix + $0 })
        if !answered.isEmpty {
            Task { await Self.withdrawDelivered { answered.contains($0) } }
        }
        settleAnswers()
        refreshVisible()
    }

    private func tick() {
        tracker.prune(now: Date())
        processes = processes.filter { tracker.sessions[$0.key] != nil }
        refreshVisible()
        // Claude Code installed after AIMeter started: its logs folder
        // appears later, and the watcher, which found none, starts now.
        watcher?.start()
    }

    private func refreshVisible() {
        let visible = tracker.visible(now: Date())
        guard visible != sessions else { return }
        let added = Set(visible.map(\.id)) != Set(sessions.map(\.id))
        sessions = visible
        if added { refreshOpenable() }
    }

    private func markFinished(_ session: ClaudeCodeSessionActivity) {
        justFinished = session
        markTask?.cancel()
        markTask = Task { [weak self] in
            try? await Task.sleep(for: Self.finishedMarkDuration)
            guard !Task.isCancelled else { return }
            self?.justFinished = nil
        }
    }
}

#endif
