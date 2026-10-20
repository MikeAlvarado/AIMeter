import Foundation
@testable import UsageKit

/// An `HTTPTransport` that answers from queued responses per URL and
/// keeps every request it was handed, for the provider tests (the Claude
/// tests carry a private twin from before this one existed).
final class RoutedTransport: HTTPTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private var routes: [URL: [(status: Int, body: String, headers: [String: String])]] = [:]
    /// How long a request to the URL takes; a cancelled caller's request
    /// throws, the way URLSession's does.
    var delays: [URL: Duration] = [:]
    var onSend: (@Sendable (URLRequest) -> Void)?

    func route(url: URL, responses: [(Int, String)]) {
        routes[url] = responses.map { ($0.0, $0.1, [:]) }
    }

    func route(url: URL, responses: [(Int, String, [String: String])]) {
        routes[url] = responses
    }

    func requests(to url: URL) -> [URLRequest] {
        requests.filter { $0.url == url }
    }

    /// The form-encoded body of a request, decoded into its pairs.
    static func form(of request: URLRequest) -> [String: String] {
        guard let body = request.httpBody, let text = String(data: body, encoding: .utf8) else { return [:] }
        var pairs: [String: String] = [:]
        for part in text.split(separator: "&") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            pairs[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
        }
        return pairs
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        onSend?(request)
        if let url = request.url, let delay = delays[url] {
            try await Task.sleep(for: delay)
        }
        guard let url = request.url, let queue = routes[url], !queue.isEmpty else {
            throw UsageError.invalidResponse("no stubbed response for \(request.url?.absoluteString ?? "nil")")
        }
        // Consume responses in order; the last one repeats.
        let next = queue[0]
        if queue.count > 1 {
            routes[url] = Array(queue.dropFirst())
        }
        let response = HTTPURLResponse(url: url, statusCode: next.status, httpVersion: nil, headerFields: next.headers)!
        return (Data(next.body.utf8), response)
    }
}

/// An unsigned JWT with the given payload, for tokens the tests read
/// claims from.
func fakeJWT(_ payload: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: payload)
    let encoded = data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJub25lIn0.\(encoded).sig"
}

func fixtureData(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw UsageError.storage("missing fixture \(name)")
    }
    return try Data(contentsOf: url)
}
