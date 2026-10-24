#if os(macOS)
import Foundation
import Network
import UsageKit

/// Where the installed Claude Code hooks (`ClaudeCodeHooks`) report: a
/// Unix socket in AIMeter's Application Support folder, so nothing listens
/// on the network and only this user can connect. Each hook is one
/// `curl --unix-socket` POST of the JSON Claude Code hands it, its path
/// saying which hook, its `ppid` the Claude Code process it ran under.
/// From an event only its name, session, folder, agent and notification
/// kind are decoded (`ClaudeCodeHookEvent`), so the prompt, a tool's input
/// or a reply never is. While answering from the island, a permission
/// request also gives what the tool would do (`ClaudeCodePermissionAsk`),
/// and its connection stays open until the user answers in the island
/// (`answer`) or it no longer matters; before each tool, a session the
/// user stopped is told to stop (`stop`). Nothing is kept, in memory past
/// that or on disk. While AIMeter isn't running there is no socket and the
/// hooks do nothing.
nonisolated final class ClaudeHookListener: @unchecked Sendable {
    static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AIMeter", isDirectory: true)
            .appendingPathComponent("claude-hooks.sock")
    }

    /// A permission request waiting for the island's answer.
    struct Ticket: Hashable, Sendable {
        let id = UUID()
    }

    /// What the island answers a permission request with.
    enum Answer: Equatable, Sendable {
        case allow, deny, stop
    }

    private let deliver: @MainActor (ClaudeCodeHookEvent, Int32?) -> Void
    private let ask: @MainActor (ClaudeCodePermissionAsk, Int32?, Ticket) -> Void
    private let queue = DispatchQueue(label: "com.mikealvarado.aimeter.claude-hooks", qos: .utility)
    private var listener: NWListener?
    /// Touched on `queue` only.
    private var waiting: [Ticket: NWConnection] = [:]
    private var stopping: Set<String> = []

    init(
        deliver: @escaping @MainActor (ClaudeCodeHookEvent, Int32?) -> Void,
        ask: @escaping @MainActor (ClaudeCodePermissionAsk, Int32?, Ticket) -> Void
    ) {
        self.deliver = deliver
        self.ask = ask
    }

    deinit { listener?.cancel() }

    func start() {
        guard listener == nil else { return }
        let socket = Self.socketURL
        try? FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A socket file left by an earlier run would make the bind fail.
        unlink(socket.path)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .unix(path: socket.path)
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        unlink(Self.socketURL.path)
        queue.async { [self] in
            waiting.values.forEach { reply($0, with: nil) }
            waiting = [:]
            stopping = []
        }
    }

    /// Answers a waiting permission request; nil lets Claude Code's own
    /// prompt decide (it was answered there, or the session went on).
    func answer(_ ticket: Ticket, with answer: Answer?) {
        queue.async { [self] in
            guard let connection = waiting.removeValue(forKey: ticket) else { return }
            reply(connection, with: answer.map(Self.permissionBody))
        }
    }

    /// Whether `session` stops before its next tool.
    func stop(_ session: String, _ on: Bool) {
        queue.async { [self] in
            if on { stopping.insert(session) } else { stopping.remove(session) }
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Request())
    }

    /// One connection's bytes so far, appended in place: a value captured
    /// from one read to the next was copied whole on every chunk, and a
    /// permission request carrying a big file took seconds.
    private final class Request: @unchecked Sendable {
        var data = Data()
    }

    /// Reads one HTTP request (headers, then `Content-Length` bytes of
    /// body) and handles it by its path.
    private func receive(on connection: NWConnection, buffer: Request) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { buffer.data.append(data) }
            if let body = Self.body(of: buffer.data) {
                handle(Self.target(of: buffer.data), body: body, on: connection)
            } else if complete || error != nil || buffer.data.count > Self.maximumRequest {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func handle(_ target: (path: String, ppid: Int32?), body: Data, on connection: NWConnection) {
        let decoder = JSONDecoder()
        switch target.path {
        case "/claude-permission":
            guard let request = try? decoder.decode(ClaudeCodePermissionAsk.self, from: body) else {
                return reply(connection, with: nil)
            }
            let ticket = Ticket()
            waiting[ticket] = connection
            // Claude Code ended the hook (the prompt answered there, the
            // session closed): forget the ticket.
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .failed, .cancelled: waiting[ticket] = nil
                default: break
                }
            }
            let ask = ask
            Task { @MainActor in ask(request, target.ppid, ticket) }
        case "/claude-pretool":
            let session = (try? decoder.decode(ClaudeCodeHookEvent.self, from: body))?.sessionId
            if let session, stopping.remove(session) != nil {
                reply(connection, with: Self.stopBody)
            } else {
                reply(connection, with: nil)
            }
        default:
            if let event = try? decoder.decode(ClaudeCodeHookEvent.self, from: body) {
                let deliver = deliver
                Task { @MainActor in deliver(event, target.ppid) }
            }
            reply(connection, with: nil)
        }
    }

    /// 200 with `body`, or 204 with none, then closes.
    private func reply(_ connection: NWConnection, with body: Data?) {
        let head = body.map { "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \($0.count)\r\nConnection: close\r\n\r\n" }
            ?? "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + (body ?? Data()), completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: Pure

    /// What the permission hook prints for each answer (Claude Code's
    /// documented `PermissionRequest` output). Stopping denies the request
    /// and interrupts the turn.
    static func permissionBody(_ answer: Answer) -> Data {
        var decision: [String: Any]
        switch answer {
        case .allow: decision = ["behavior": "allow"]
        case .deny: decision = ["behavior": "deny", "message": "Denied from AIMeter."]
        case .stop: decision = ["behavior": "deny", "message": "Stopped from AIMeter.", "interrupt": true]
        }
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])) ?? Data()
    }

    /// What the check before a tool prints for a stopped session.
    static let stopBody = Data(#"{"continue":false,"stopReason":"Stopped from AIMeter."}"#.utf8)

    /// The request line's path and its `ppid`, when it has a number.
    static func target(of request: Data) -> (path: String, ppid: Int32?) {
        let line = String(decoding: request.prefix(while: { $0 != 13 && $0 != 10 }), as: UTF8.self)
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let components = URLComponents(string: String(parts[1])) else { return ("", nil) }
        let ppid = components.queryItems?.first { $0.name == "ppid" }?.value.flatMap { Int32($0) }
        return (components.path, ppid.flatMap { $0 > 1 ? $0 : nil })
    }

    /// A permission request carries the tool's input, a whole file for a
    /// write: room for that, and a bound on anything else.
    static let maximumRequest = 32 * 1_048_576

    /// The request's body once all of it has arrived, else nil. A length
    /// that isn't a count of bytes (negative) reads as none, rather than
    /// trapping in `prefix`.
    static func body(of request: Data) -> Data? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = request.range(of: separator) else { return nil }
        let head = String(decoding: request[..<range.lowerBound], as: UTF8.self)
        let declared = head
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
        let length = max(0, declared)
        let body = request[range.upperBound...]
        return body.count >= length ? Data(body.prefix(length)) : nil
    }
}
#endif
