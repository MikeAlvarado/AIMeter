import Foundation

/// Tokens and equivalent cost over a set of entries, in total and per
/// model — what a "Today / This week / This month / All time" bucket shows.
public struct ClaudeCodeUsageAggregate: Equatable, Sendable {
    public struct ModelUsage: Equatable, Sendable {
        public let model: String
        public let tokens: ClaudeCodeTokenCounts
        /// nil when the pricing table doesn't know this model.
        public let cost: Double?
        public let messages: Int
    }

    public let tokens: ClaudeCodeTokenCounts
    /// Sum over the models the table prices; nil only when nothing in the
    /// bucket could be priced.
    public let cost: Double?
    /// True when at least one model in the bucket has no price, so the
    /// shown cost is a lower bound.
    public let hasUnpricedModels: Bool
    public let messages: Int
    public let sessions: Int
    /// Most tokens first.
    public let byModel: [ModelUsage]

    public init(entries: [ClaudeCodeUsageEntry]) {
        var perModel: [String: (tokens: ClaudeCodeTokenCounts, cost: Double?, priced: Bool, messages: Int)] = [:]
        var sessionIDs: Set<String> = []
        for entry in entries {
            sessionIDs.insert(entry.sessionID)
            var slot = perModel[entry.model] ?? (ClaudeCodeTokenCounts(), nil, true, 0)
            slot.tokens = slot.tokens + entry.tokens
            slot.messages += 1
            if let cost = entry.cost {
                slot.cost = (slot.cost ?? 0) + cost
            } else {
                slot.priced = false
            }
            perModel[entry.model] = slot
        }
        let models = perModel.map { model, slot in
            ModelUsage(model: model, tokens: slot.tokens, cost: slot.priced ? slot.cost : nil, messages: slot.messages)
        }.sorted { $0.tokens.total > $1.tokens.total }
        byModel = models
        tokens = models.reduce(ClaudeCodeTokenCounts()) { $0 + $1.tokens }
        let priced = models.compactMap(\.cost)
        cost = priced.isEmpty ? nil : priced.reduce(0, +)
        hasUnpricedModels = models.contains { $0.cost == nil }
        messages = entries.count
        sessions = sessionIDs.count
    }

    /// The entries inside `interval` (nil = everything).
    public static func entries(_ entries: [ClaudeCodeUsageEntry], in interval: DateInterval?) -> [ClaudeCodeUsageEntry] {
        guard let interval else { return entries }
        return entries.filter { interval.contains($0.timestamp) }
    }

    // MARK: - The buckets

    /// Calendar-local "today" (since local midnight), ending at `now`.
    public static func today(now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        DateInterval(start: calendar.startOfDay(for: now), end: now)
    }

    /// The last `days` × 24 hours, ending at `now`. Rolling rather than
    /// calendar weeks/months on purpose: on the 2nd of a month a calendar
    /// "this month" holds two days while "this week" holds five, and the
    /// month row reads smaller than the week row — true, and baffling.
    /// Rolling windows nest (today ⊂ 7 days ⊂ 30 days), so the rows only
    /// ever grow downwards, and they match the History chart's ranges.
    public static func last(days: Int, now: Date = Date()) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-Double(days) * 86_400), end: now)
    }
}
