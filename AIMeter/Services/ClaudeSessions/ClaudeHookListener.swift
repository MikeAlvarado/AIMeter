#if os(macOS)
import Foundation
import Network
import UsageKit

/// Where the installed Claude Code hooks (`ClaudeCodeHooks`) report: a
/// Unix socket in AIMeter's Application Support folder, so nothing listens
/// on the network and only this user can connect. Each hook is one
/// `curl --unix-socket` POST of the JSON Claude Code hands it; only the
/// event's name, session, folder, agent and notification kind are decoded
/// (`ClaudeCodeHookEvent`), so the prompt, a tool's input or a reply never
/// is, and nothing is kept, in memory or on disk. While AIMeter isn't
/// running there is no socket and the hook does nothing.
nonisolated final class ClaudeHookListener: @unchecked Sendable {
    static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AIMeter", isDirectory: true)
            .appendingPathComponent("claude-hooks.sock")
    }

    private let deliver: @MainActor (ClaudeCodeHookEvent) -> Void
    private let queue = DispatchQueue(label: "com.mikealvarado.aimeter.claude-hooks", qos: .utility)
    private var listener: NWListener?

    init(deliver: @escaping @MainActor (ClaudeCodeHookEvent) -> Void) {
        self.deliver = deliver
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
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    /// Reads one HTTP request (headers, then `Content-Length` bytes of
    /// body), answers 204 and closes.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let body = Self.body(of: buffer) {
                if let event = try? JSONDecoder().decode(ClaudeCodeHookEvent.self, from: body) {
                    let deliver = self.deliver
                    Task { @MainActor in deliver(event) }
                }
                let reply = Data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
            } else if complete || error != nil || buffer.count > Self.maximumRequest {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    /// A permission request carries the tool's input, a whole file for a
    /// write: room for that, and a bound on anything else.
    static let maximumRequest = 32 * 1_048_576

    /// The request's body once all of it has arrived, else nil.
    static func body(of request: Data) -> Data? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = request.range(of: separator) else { return nil }
        let head = String(decoding: request[..<range.lowerBound], as: UTF8.self)
        let length = head
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
        let body = request[range.upperBound...]
        return body.count >= length ? Data(body.prefix(length)) : nil
    }
}
#endif
