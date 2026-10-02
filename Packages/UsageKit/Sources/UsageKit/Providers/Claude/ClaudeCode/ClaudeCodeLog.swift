import Foundation

/// Token counts of one API message as Claude Code logs them. `output`
/// already includes thinking tokens (`output_tokens_details.thinking_tokens`
/// is a breakdown, not an addition); the cache-write split comes from
/// `cache_creation.ephemeral_5m/1h_input_tokens` when present, else the
/// whole `cache_creation_input_tokens` counts as 5-minute writes.
public struct ClaudeCodeTokenCounts: Codable, Equatable, Sendable {
    public var input = 0
    public var output = 0
    public var thinking = 0
    public var cacheWrite5m = 0
    public var cacheWrite1h = 0
    public var cacheRead = 0
    public var webSearches = 0

    public init(input: Int = 0, output: Int = 0, thinking: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0, cacheRead: Int = 0, webSearches: Int = 0) {
        self.input = input
        self.output = output
        self.thinking = thinking
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
        self.webSearches = webSearches
    }

    public var total: Int { input + output + cacheWrite5m + cacheWrite1h + cacheRead }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            input: lhs.input + rhs.input, output: lhs.output + rhs.output, thinking: lhs.thinking + rhs.thinking,
            cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m, cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h,
            cacheRead: lhs.cacheRead + rhs.cacheRead, webSearches: lhs.webSearches + rhs.webSearches
        )
    }
}

/// One deduplicated assistant message from the logs — the unit the
/// time-bucketed aggregates are built from.
public struct ClaudeCodeUsageEntry: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let model: String
    public let sessionID: String
    public let tokens: ClaudeCodeTokenCounts

    public init(timestamp: Date, model: String, sessionID: String, tokens: ClaudeCodeTokenCounts) {
        self.timestamp = timestamp
        self.model = model
        self.sessionID = sessionID
        self.tokens = tokens
    }

    /// Equivalent API cost at list prices, nil for a model the pricing
    /// table doesn't know.
    public var cost: Double? { ClaudeModelPricing.cost(tokens, model: model) }
}

/// Claude Code's own running total for a session (`type: "cost-state"`,
/// cumulative — the last record in a file is the session's total). Kept
/// as a cross-check of the pricing table, not as the displayed figure:
/// it carries no time, so it can't feed the day/week/month buckets.
public struct ClaudeCodeSessionTotal: Codable, Equatable, Sendable {
    public let sessionID: String
    public let totalCostUSD: Double
    public let hasUnknownModelCost: Bool

    public init(sessionID: String, totalCostUSD: Double, hasUnknownModelCost: Bool) {
        self.sessionID = sessionID
        self.totalCostUSD = totalCostUSD
        self.hasUnknownModelCost = hasUnknownModelCost
    }
}

/// One parsed JSONL line, reduced to the fields AIMeter reads. The
/// `Decodable`s below declare only those fields, so conversation content
/// is never decoded, by construction.
public enum ClaudeCodeLogLine: Equatable, Sendable {
    case assistant(entry: ClaudeCodeUsageEntry, messageID: String?, requestID: String?)
    case costState(ClaudeCodeSessionTotal)

    /// nil for any other record type, or a line that doesn't parse —
    /// one bad line never takes a file down.
    public static func parse(_ line: Data, fallbackSessionID: String) -> ClaudeCodeLogLine? {
        guard let record = try? JSONDecoder.claudeCode.decode(Record.self, from: line) else { return nil }
        switch record.type {
        case "assistant":
            guard let message = record.message, let usage = message.usage, let model = message.model,
                  let timestamp = record.timestamp else { return nil }
            let creation = usage.cacheCreation
            let write5m = creation?.ephemeral5m ?? usage.cacheCreationInputTokens ?? 0
            let write1h = creation?.ephemeral1h ?? 0
            let tokens = ClaudeCodeTokenCounts(
                input: usage.inputTokens ?? 0,
                output: usage.outputTokens ?? 0,
                thinking: usage.outputTokensDetails?.thinkingTokens ?? 0,
                cacheWrite5m: write5m,
                cacheWrite1h: write1h,
                cacheRead: usage.cacheReadInputTokens ?? 0,
                webSearches: usage.serverToolUse?.webSearchRequests ?? 0
            )
            let entry = ClaudeCodeUsageEntry(
                timestamp: timestamp, model: model, sessionID: record.sessionId ?? fallbackSessionID, tokens: tokens
            )
            return .assistant(entry: entry, messageID: message.id, requestID: record.requestId)
        case "cost-state":
            guard let total = record.totalCostUSD else { return nil }
            return .costState(ClaudeCodeSessionTotal(
                sessionID: record.sessionId ?? fallbackSessionID,
                totalCostUSD: total,
                hasUnknownModelCost: record.hasUnknownModelCost ?? false
            ))
        default:
            return nil
        }
    }

    // MARK: - Wire shape (only what's read)

    private struct Record: Decodable {
        let type: String
        let timestamp: Date?
        let requestId: String?
        let sessionId: String?
        let message: Message?
        let totalCostUSD: Double?
        let hasUnknownModelCost: Bool?
    }

    private struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?
    }

    private struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreation: CacheCreation?
        let outputTokensDetails: OutputDetails?
        let serverToolUse: ServerToolUse?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreation = "cache_creation"
            case outputTokensDetails = "output_tokens_details"
            case serverToolUse = "server_tool_use"
        }
    }

    private struct CacheCreation: Decodable {
        let ephemeral5m: Int?
        let ephemeral1h: Int?

        enum CodingKeys: String, CodingKey {
            case ephemeral5m = "ephemeral_5m_input_tokens"
            case ephemeral1h = "ephemeral_1h_input_tokens"
        }
    }

    private struct OutputDetails: Decodable {
        let thinkingTokens: Int?

        enum CodingKeys: String, CodingKey {
            case thinkingTokens = "thinking_tokens"
        }
    }

    private struct ServerToolUse: Decodable {
        let webSearchRequests: Int?

        enum CodingKeys: String, CodingKey {
            case webSearchRequests = "web_search_requests"
        }
    }
}

extension JSONDecoder {
    /// Claude Code writes ISO 8601 with fractional seconds.
    static let claudeCode: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = formatter.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(text)"))
        }
        return decoder
    }()
}
