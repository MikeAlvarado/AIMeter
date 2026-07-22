import Foundation

/// A single rolling usage window reported by a provider, e.g. the 5-hour
/// session window or a per-model weekly window.
public struct UsageWindow: Codable, Hashable, Sendable {
    /// The category of a usage window. Extensible: providers that expose
    /// per-model limits use `.modelSpecific` with the model's display name
    /// exactly as the provider reports it (e.g. "Fable").
    public enum Kind: Hashable, Sendable {
        case session
        case weekly
        case modelSpecific(String)
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

    public init(
        kind: Kind,
        usedPct: Double,
        resetsAt: Date? = nil,
        severity: Severity? = nil,
        isActive: Bool? = nil
    ) {
        self.kind = kind
        self.usedPct = usedPct
        self.resetsAt = resetsAt
        self.severity = severity
        self.isActive = isActive
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
            guard storageKey.hasPrefix("model.") else { return nil }
            self = .modelSpecific(String(storageKey.dropFirst("model.".count)))
        }
    }
}

extension UsageWindow.Kind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case model
    }

    private enum KindType: String, Codable {
        case session
        case weekly
        case modelSpecific
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
        case .credits:
            try container.encode(KindType.credits, forKey: .type)
        }
    }
}
