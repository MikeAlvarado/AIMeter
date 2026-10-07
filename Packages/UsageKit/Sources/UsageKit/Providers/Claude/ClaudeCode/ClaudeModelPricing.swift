import Foundation

/// Per-million-token list prices for the models Claude Code logs, used to
/// put an equivalent API cost on local usage. Hardcoded and updated per
/// release — this project has no server to fetch from, and most users
/// can't verify a table they'd hand-edit — with `lastVerified` surfaced in
/// the UI, the same honesty mechanism `ClaudePeakSchedule` used: a stale
/// table is never presented as live truth.
///
/// Source: platform.claude.com/docs/en/about-claude/pricing, "Model
/// pricing" and "Prompt caching" (5-minute writes 1.25× input, 1-hour
/// writes 2× input, cache reads 0.1× — 0.025× on Fable 5.1 / Mythos 5.1,
/// 0.05× on Opus 5.5), and "Web search tool" ($10 per 1,000 searches;
/// web fetch is free). Haiku 5.5 is the one model priced by prompt
/// length: a second set of rates applies to a request whose prompt
/// (input plus every cache category) exceeds 100,000 tokens.
public enum ClaudeModelPricing {
    /// When the table below was last checked against the pricing page.
    public static let lastVerified = Date(timeIntervalSince1970: 1_791_331_200) // 2026-10-07

    /// USD per million tokens.
    public struct Rates: Equatable, Sendable {
        public let input: Double
        public let cacheWrite5m: Double
        public let cacheWrite1h: Double
        public let cacheRead: Double
        public let output: Double
        /// The rates for a request whose prompt exceeds `longPromptThreshold`
        /// tokens, for the models priced by prompt length; nil when one
        /// price applies regardless.
        public let longPrompt: LongPrompt?

        public struct LongPrompt: Equatable, Sendable {
            public let input: Double
            public let cacheWrite5m: Double
            public let cacheWrite1h: Double
            public let cacheRead: Double
            public let output: Double

            public init(input: Double, cacheWrite5m: Double, cacheWrite1h: Double, cacheRead: Double, output: Double) {
                self.input = input
                self.cacheWrite5m = cacheWrite5m
                self.cacheWrite1h = cacheWrite1h
                self.cacheRead = cacheRead
                self.output = output
            }
        }

        public init(input: Double, cacheWrite5m: Double, cacheWrite1h: Double, cacheRead: Double, output: Double, longPrompt: LongPrompt? = nil) {
            self.input = input
            self.cacheWrite5m = cacheWrite5m
            self.cacheWrite1h = cacheWrite1h
            self.cacheRead = cacheRead
            self.output = output
            self.longPrompt = longPrompt
        }
    }

    /// Prompt size (input + cache writes + cache reads) above which a
    /// model's `longPrompt` rates apply.
    public static let longPromptThreshold = 100_000

    /// USD per web search request.
    public static let webSearchRequest = 10.0 / 1000

    /// Keyed by the model id *prefix* Claude Code writes in `message.model`
    /// — a dated snapshot id (`claude-opus-4-5-20251101`) matches its
    /// undated family. Order doesn't matter: `rates(for:)` takes the
    /// longest prefix that matches as a whole id component, so
    /// `claude-opus-5` never swallows `claude-opus-5-5`.
    public static let table: [String: Rates] = [
        "claude-fable-5-1": Rates(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 0.25, output: 50),
        "claude-mythos-5-1": Rates(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 0.25, output: 50),
        "claude-fable-5": Rates(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 1, output: 50),
        "claude-mythos-5": Rates(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 1, output: 50),
        "claude-opus-5-5": Rates(input: 4, cacheWrite5m: 5, cacheWrite1h: 8, cacheRead: 0.20, output: 20),
        "claude-opus-5": Rates(input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.50, output: 25),
        "claude-opus-4-8": Rates(input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.50, output: 25),
        "claude-opus-4-7": Rates(input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.50, output: 25),
        "claude-opus-4-6": Rates(input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.50, output: 25),
        "claude-opus-4-5": Rates(input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.50, output: 25),
        "claude-opus-4-1": Rates(input: 15, cacheWrite5m: 18.75, cacheWrite1h: 30, cacheRead: 1.50, output: 75),
        "claude-opus-4": Rates(input: 15, cacheWrite5m: 18.75, cacheWrite1h: 30, cacheRead: 1.50, output: 75),
        "claude-sonnet-5-5": Rates(input: 2, cacheWrite5m: 2.5, cacheWrite1h: 4, cacheRead: 0.20, output: 10),
        "claude-sonnet-5": Rates(input: 2, cacheWrite5m: 2.5, cacheWrite1h: 4, cacheRead: 0.20, output: 10),
        "claude-sonnet-4-6": Rates(input: 3, cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.30, output: 15),
        "claude-sonnet-4-5": Rates(input: 3, cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.30, output: 15),
        "claude-sonnet-4": Rates(input: 3, cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.30, output: 15),
        "claude-haiku-5-5": Rates(
            input: 0.10, cacheWrite5m: 0.125, cacheWrite1h: 0.20, cacheRead: 0.01, output: 0.50,
            longPrompt: .init(input: 0.50, cacheWrite5m: 0.625, cacheWrite1h: 1, cacheRead: 0.05, output: 2.50)
        ),
        "claude-haiku-4-5": Rates(input: 1, cacheWrite5m: 1.25, cacheWrite1h: 2, cacheRead: 0.10, output: 5),
        "claude-3-5-haiku": Rates(input: 0.80, cacheWrite5m: 1, cacheWrite1h: 1.60, cacheRead: 0.08, output: 4),
    ]

    /// The rates for a logged model id, or nil for a model the table
    /// doesn't know — the UI then shows its tokens with no cost rather than
    /// guessing one.
    public static func rates(for model: String) -> Rates? {
        var best: (prefix: String, rates: Rates)?
        for (prefix, rates) in table where matches(model, prefix: prefix) {
            if best == nil || prefix.count > best!.prefix.count {
                best = (prefix, rates)
            }
        }
        return best?.rates
    }

    /// `prefix` is the id itself, or the id followed by `-` and a date
    /// snapshot (digits only) — never a longer family id.
    static func matches(_ model: String, prefix: String) -> Bool {
        if model == prefix { return true }
        guard model.hasPrefix(prefix + "-") else { return false }
        let rest = model.dropFirst(prefix.count + 1)
        return !rest.isEmpty && rest.allSatisfy(\.isNumber)
    }

    /// Equivalent API cost in USD for one message's counts, nil for an
    /// unknown model.
    public static func cost(_ tokens: ClaudeCodeTokenCounts, model: String) -> Double? {
        guard let rates = rates(for: model) else { return nil }
        let perToken = 1.0 / 1_000_000
        let prompt = tokens.input + tokens.cacheWrite5m + tokens.cacheWrite1h + tokens.cacheRead
        if let long = rates.longPrompt, prompt > longPromptThreshold {
            return Double(tokens.input) * long.input * perToken
                + Double(tokens.cacheWrite5m) * long.cacheWrite5m * perToken
                + Double(tokens.cacheWrite1h) * long.cacheWrite1h * perToken
                + Double(tokens.cacheRead) * long.cacheRead * perToken
                + Double(tokens.output) * long.output * perToken
                + Double(tokens.webSearches) * webSearchRequest
        }
        return Double(tokens.input) * rates.input * perToken
            + Double(tokens.cacheWrite5m) * rates.cacheWrite5m * perToken
            + Double(tokens.cacheWrite1h) * rates.cacheWrite1h * perToken
            + Double(tokens.cacheRead) * rates.cacheRead * perToken
            + Double(tokens.output) * rates.output * perToken
            + Double(tokens.webSearches) * webSearchRequest
    }
}
