import Foundation
import UsageKit

/// Every account's usage history as a file the user takes elsewhere: a
/// CSV for Numbers or Excel, or a JSON for a script. Built from what the
/// app already keeps (the chart's timeline, `UsageTimelineStore`, and the
/// last snapshot per account); nothing is fetched and nothing leaves the
/// device but the file, where the user sends it. Pure, so the shape is
/// tested without a file system.
nonisolated struct UsageExport: Sendable {
    /// One account's part: its nickname, provider family, history per
    /// window (keyed by `UsageWindow.Kind.storageKey`) and last snapshot.
    struct Account: Sendable {
        let name: String
        let providerID: String
        let history: [String: [TimelineSample]]
        let latest: UsageSnapshot?
    }

    enum Format: String, Sendable {
        case csv, json

        var fileExtension: String { rawValue }
    }

    /// The shape of the JSON document; bumped if a field ever changes
    /// meaning, so a script can tell what it has.
    static let formatVersion = 1

    let accounts: [Account]
    let exportedAt: Date

    /// "AIMeter usage 2026-10-19.csv": the day in the user's calendar, so
    /// two exports a day apart sort and read apart.
    func fileName(_ format: Format) -> String {
        let day = Self.dayFormatter.string(from: exportedAt)
        return "AIMeter usage \(day).\(format.fileExtension)"
    }

    func data(_ format: Format) throws -> Data {
        switch format {
        case .csv: Data(csv().utf8)
        case .json: try json()
        }
    }

    // MARK: - CSV

    /// One sample per row, accounts in their order, windows in the order
    /// the app shows them (session, weekly, the models, credits), samples
    /// in time order. Dates are ISO 8601 in UTC and numbers use a point
    /// whatever the device's locale: the file is data, not prose.
    func csv() -> String {
        var lines = ["account,provider,window,timestamp,used_pct,resets_at"]
        for account in accounts {
            for key in Self.orderedKeys(account.history.keys) {
                for sample in account.history[key] ?? [] {
                    lines.append([
                        Self.field(account.name),
                        Self.field(account.providerID),
                        Self.field(key),
                        Self.iso.string(from: sample.timestamp),
                        Self.number(sample.usedPct),
                        sample.resetsAt.map(Self.iso.string(from:)) ?? "",
                    ].joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Quoted when the value has a comma, a quote or a line break in it,
    /// with quotes doubled, as RFC 4180 has it.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// "42", "42.5", "100": whole numbers without a decimal part, others
    /// with at most two, always with a point (`String(format:)` without a
    /// locale is the C locale's).
    static func number(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int(value)) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// Session, weekly, the per-model windows by name, the quotas by
    /// name, then the rest.
    static func orderedKeys<S: Sequence>(_ keys: S) -> [String] where S.Element == String {
        keys.sorted { lhs, rhs in
            let (l, r) = (rank(lhs), rank(rhs))
            return l == r ? lhs < rhs : l < r
        }
    }

    private static func rank(_ key: String) -> Int {
        switch UsageWindow.Kind(storageKey: key) {
        case .session: 0
        case .weekly: 1
        case .modelSpecific: 2
        case .quota: 3
        case .credits: 4
        case nil: 5
        }
    }

    // MARK: - JSON

    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Document(export: self))
    }

    struct Document: Codable {
        var app = "AIMeter"
        var format = UsageExport.formatVersion
        let exportedAt: Date
        let accounts: [AccountRecord]

        init(export: UsageExport) {
            exportedAt = export.exportedAt
            accounts = export.accounts.map(AccountRecord.init)
        }
    }

    struct AccountRecord: Codable {
        let name: String
        let provider: String
        let latest: Latest?
        let history: [String: [Sample]]

        init(_ account: Account) {
            name = account.name
            provider = account.providerID
            latest = account.latest.map(Latest.init)
            history = account.history.mapValues { $0.map(Sample.init) }
        }
    }

    struct Latest: Codable {
        let fetchedAt: Date
        let plan: String?
        let windows: [Window]
        let spend: Spend?

        init(_ snapshot: UsageSnapshot) {
            fetchedAt = snapshot.fetchedAt
            plan = snapshot.planName
            windows = snapshot.windows.map(Window.init)
            spend = snapshot.spend.map(Spend.init)
        }
    }

    struct Window: Codable {
        let window: String
        let usedPct: Double
        let resetsAt: Date?
        let severity: String?

        init(_ window: UsageWindow) {
            self.window = window.kind.storageKey
            usedPct = window.usedPct
            resetsAt = window.resetsAt
            severity = window.severity?.rawValue
        }
    }

    struct Spend: Codable {
        let enabled: Bool
        let percent: Double?
        let usedAmount: Double?
        let limitAmount: Double?
        let currency: String?

        init(_ spend: SpendStatus) {
            enabled = spend.enabled
            percent = spend.percent
            usedAmount = spend.usedAmount
            limitAmount = spend.limitAmount
            currency = spend.currency
        }
    }

    struct Sample: Codable {
        let timestamp: Date
        let usedPct: Double
        let resetsAt: Date?

        init(_ sample: TimelineSample) {
            timestamp = sample.timestamp
            usedPct = sample.usedPct
            resetsAt = sample.resetsAt
        }
    }

    // MARK: - Formatters

    private static let iso = ISO8601DateFormatter()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
