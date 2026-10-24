#if os(macOS)
import AppKit
import UsageKit

/// What `ClaudeSessionMonitor` does for the island's buttons: the
/// permission prompts it can answer ("Answer from the island", through the
/// hooks' answering mode), the sessions the user stopped, and which app
/// each session opens in. Split from the monitor to keep it readable; the
/// members it shares with it are internal for that reason.
extension ClaudeSessionMonitor {
    // MARK: Answering

    /// A permission prompt the island can answer: the session is waiting,
    /// for the tracker as for the island.
    func receive(_ request: ClaudeCodePermissionAsk, pid: Int32?, ticket: ClaudeHookListener.Ticket) {
        guard answers else {
            listener?.answer(ticket, with: nil)
            return
        }
        if let previous = asks[request.sessionId] { listener?.answer(previous.ticket, with: nil) }
        asks[request.sessionId] = PermissionAsk(request: request, ticket: ticket)
        apply(request.event, pid: pid)
        if stopping.contains(request.sessionId) { answer(request.sessionId, with: .stop) }
    }

    func approve(_ session: String) {
        answer(session, with: .allow)
    }

    func deny(_ session: String) {
        answer(session, with: .deny)
    }

    /// Stops `session` before its next tool, or now, when it waits for a
    /// prompt the island can answer.
    func stopSession(_ session: String) {
        guard answers else { return }
        stopping.insert(session)
        listener?.stop(session, true)
        if asks[session] != nil { answer(session, with: .stop) }
    }

    private func answer(_ session: String, with answer: ClaudeHookListener.Answer) {
        guard let ask = asks.removeValue(forKey: session) else { return }
        listener?.answer(ask.ticket, with: answer)
    }

    /// Lets Claude Code's own prompts decide every open request.
    func withdrawAsks() {
        asks.values.forEach { listener?.answer($0.ticket, with: nil) }
        asks = [:]
        stopping.forEach { listener?.stop($0, false) }
        stopping = []
    }

    /// Prompts answered in Claude Code (or ended) go back to it, and a
    /// stop lasts until the turn it was asked in ends.
    func settleAnswers() {
        for (id, ask) in asks where !(tracker.sessions[id]?.isAskingPermission ?? false) {
            listener?.answer(ask.ticket, with: nil)
            asks[id] = nil
        }
        for id in stopping where !(tracker.sessions[id]?.isActive ?? false) {
            listener?.stop(id, false)
            stopping.remove(id)
        }
    }

    // MARK: Opening

    /// Brings up the app `session` lives in.
    func open(_ session: String) {
        opener.open(session, pid: processes[session])
    }

    func remember(_ pid: Int32, for session: String) {
        guard processes[session] != pid else { return }
        processes[session] = pid
        refreshOpenable()
    }

    func refreshOpenable() {
        let ids = sessions.map(\.id)
        var targets: [String: String] = [:]
        for id in ids {
            if let place = opener.place(of: id) {
                targets[id] = place.app.deletingPathExtension().lastPathComponent
            } else if let pid = processes[id], let app = ClaudeSessionOpener.owningApp(of: pid), let name = app.localizedName {
                targets[id] = name
            }
        }
        if targets != openTargets { openTargets = targets }
        opener.refresh(for: ids) { [weak self] in self?.refreshOpenable() }
    }
}
#endif
