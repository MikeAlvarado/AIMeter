import Foundation

/// A single rolling usage window reported by a provider, e.g. the 5-hour
/// session window or a per-model weekly window.
public struct UsageWindow: Codable, Hashable, Sendable {
    /// The category of a usage window. Extensible: providers that expose
    /// per-model limits use `.modelSpecific` with the model's display name
    /// exactly as the provider reports it (e.g. "Fable"), and a provider
    /// whose allowances are neither a session nor an overall period
    /// uses `.quota` with its own stable name for each.
    public enum Kind: Hashable, Sendable {
        /// The short rolling window usage starts on first use: Claude's and
        /// Codex's 5 hours.
        case session
        /// The overall periodic allowance: a week for Claude and paid
        /// Codex plans, a month for Codex Free. The length is the window's
        /// `duration`, not the kind.
        case weekly
        case modelSpecific(String)
        /// A named allowance the provider meters on its own calendar and
        /// nothing else fits: GitHub Copilot's monthly premium requests,
        /// chat and completions. The string is the provider's stable
        /// identifier for it (`premium_interactions`), never a display
        /// name, so persistence keys stay the same in every language; the
        /// presentation layer names it. Its length rides in `duration`.
        case quota(String)
        /// Display-only pseudo-window synthesized by the presentation layer
        /// from `SpendStatus` (e.g. when a plan bills a model via usage
        /// credits instead of its own rate-limit window). Never produced by
        /// provider mapping code and never appears in a persisted
        /// `UsageSnapshot.windows` array.
        case credits
    }

    /// Provider-reported urgency of the window, when available.
    public enum Severity: String, Codable, Sendable {
        case normal
        case warning
        case critical
        case exceeded
    }

    public var kind: Kind
    /// Percentage of the window's limit already used, 0–100.
    public var usedPct: Double
    /// When the window rolls over and usage resets, if the provider reports it.
    public var resetsAt: Date?
    public var severity: Severity?
    /// Whether the provider considers this window currently active.
    public var isActive: Bool?
    /// The window's nominal length, when the provider states it (Claude:
    /// 5 h sessions, 7-day weeks). Pace and run-out math read
    /// `effectiveDuration`, which falls back to the kind's Claude-shaped
    /// default when this is nil — so a provider whose "weekly" is a
    /// calendar month, or whose session is 3 h, sets this instead of
    /// needing a new `Kind`. Optional in the persisted shape, so snapshots
    /// saved before it existed still decode.
    public var duration: TimeInterval?

    public init(
        kind: Kind,
        usedPct: Double,
        resetsAt: Date? = nil,
        severity: Severity? = nil,
        isActive: Bool? = nil,
        duration: TimeInterval? = nil
    ) {
        self.kind = kind
        self.usedPct = usedPct
        self.resetsAt = resetsAt
        self.severity = severity
        self.isActive = isActive
        self.duration = duration
    }

    /// The length pace/run-out math uses: the provider's own `duration`
    /// when set, else `Kind.windowDuration`'s default.
    public var effectiveDuration: TimeInterval? {
        duration ?? kind.windowDuration
    }

    /// Remaining percentage of the window's limit, 0–100.
    public var remainingPct: Double {
        max(0, min(100, 100 - usedPct))
    }
}

extension UsageWindow.Kind {
    /// Stable string identifier for a kind, used as a persistence key for
    /// per-window state: notification toggles, widget configuration option
    /// IDs, and usage-history buckets. Round-trips through `init?(storageKey:)`.
    public var storageKey: String {
        switch self {
        case .session: return "session"
        case .weekly: return "weekly"
        case .modelSpecific(let model): return "model.\(model)"
        case .quota(let name): return "quota.\(name)"
        case .credits: return "credits"
        }
    }

    /// Reverses `storageKey`, e.g. for widget configuration options
    /// persisted as strings.
    public init?(storageKey: String) {
        switch storageKey {
        case "session": self = .session
        case "weekly": self = .weekly
        case "credits": self = .credits
        default:
            if storageKey.hasPrefix("model.") {
                self = .modelSpecific(String(storageKey.dropFirst("model.".count)))
            } else if storageKey.hasPrefix("quota.") {
                self = .quota(String(storageKey.dropFirst("quota.".count)))
            } else {
                return nil
            }
        }
    }

    /// Whether this is a per-model window.
    public var isModelSpecific: Bool {
        if case .modelSpecific = self { return true }
        return false
    }

    /// Whether this is a named quota.
    public var isQuota: Bool {
        if case .quota = self { return true }
        return false
    }
}

extension UsageWindow.Kind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case model
        case quota
    }

    private enum KindType: String, Codable {
        case session
        case weekly
        case modelSpecific
        case quota
        case credits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(KindType.self, forKey: .type) {
        case .session:
            self = .session
        case .weekly:
            self = .weekly
        case .modelSpecific:
            self = .modelSpecific(try container.decode(String.self, forKey: .model))
        case .quota:
            self = .quota(try container.decode(String.self, forKey: .quota))
        case .credits:
            self = .credits
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .session:
            try container.encode(KindType.session, forKey: .type)
        case .weekly:
            try container.encode(KindType.weekly, forKey: .type)
        case .modelSpecific(let model):
            try container.encode(KindType.modelSpecific, forKey: .type)
            try container.encode(model, forKey: .model)
        case .quota(let name):
            try container.encode(KindType.quota, forKey: .type)
            try container.encode(name, forKey: .quota)
        case .credits:
            try container.encode(KindType.credits, forKey: .type)
        }
    }
}
