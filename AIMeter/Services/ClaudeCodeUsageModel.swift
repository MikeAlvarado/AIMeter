#if os(macOS)
import Foundation
import Observation
import UsageKit

/// Claude Code's token usage on this Mac, read from its local logs through
/// `ClaudeCodeLogReader` (UsageKit) and priced at API list rates. macOS
/// only and opt-in (`Preferences.claudeCodeUsageEnabled`, off by default):
/// the logs are another app's files, and the same files hold the
/// conversations — only the usage fields are ever decoded, but the user
/// decides whether AIMeter opens them at all. It is a property of the
/// machine, not of a connected account: the CLI's login may or may not be
/// one of them, so it has its own Dashboard section rather than a row
/// under an account.
@MainActor
@Observable
final class ClaudeCodeUsageModel {
    enum Bucket: CaseIterable {
        case today, week, month, all

        var label: String {
            switch self {
            case .today: String(localized: "Today")
            case .week: String(localized: "This week")
            case .month: String(localized: "This month")
            case .all: String(localized: "All time")
            }
        }

        func interval(now: Date, calendar: Calendar) -> DateInterval? {
            switch self {
            case .today: ClaudeCodeUsageAggregate.today(now: now, calendar: calendar)
            case .week: ClaudeCodeUsageAggregate.thisWeek(now: now, calendar: calendar)
            case .month: ClaudeCodeUsageAggregate.thisMonth(now: now, calendar: calendar)
            case .all: nil
            }
        }
    }

    private(set) var ledger = ClaudeCodeUsageLedger()
    private(set) var isScanning = false
    private(set) var enabled: Bool
    let root: URL
    let indexURL: URL
    @ObservationIgnored private let reader: ClaudeCodeLogReader
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    /// Where Claude Code keeps its session logs.
    nonisolated static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// The reader's own index — paths, byte offsets and the deduplicated
    /// entries — in AIMeter's Application Support, never next to the logs.
    nonisolated static var defaultIndexURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("AIMeter/claude-code-usage.json", isDirectory: false)
    }

    init(root: URL = defaultRoot, indexURL: URL = defaultIndexURL, enabled: Bool) {
        self.root = root
        self.indexURL = indexURL
        self.enabled = enabled
        reader = ClaudeCodeLogReader(root: root, indexURL: indexURL)
        if enabled {
            // Show what the last run left before the first scan lands.
            Task { ledger = await reader.currentLedger() }
        }
    }

    /// Whether Claude Code has ever run on this Mac — the invitation card
    /// is pointless otherwise.
    var logsExist: Bool {
        FileManager.default.fileExists(atPath: root.path)
    }

    /// Called from the refresh sweeps; a no-op while off or mid-scan.
    func rescanIfEnabled() {
        guard enabled else { return }
        rescan()
    }

    func rescan() {
        guard scanTask == nil else { return }
        isScanning = true
        scanTask = Task {
            await scan()
            scanTask = nil
        }
    }

    /// The scan itself, awaited by the tests.
    func scan() async {
        isScanning = true
        let result = await reader.scan()
        ledger = result
        isScanning = false
    }

    /// Off also forgets the index: nothing of the logs stays behind once
    /// the user says no.
    func setEnabled(_ on: Bool) {
        guard enabled != on else { return }
        enabled = on
        if on {
            rescan()
        } else {
            scanTask?.cancel()
            scanTask = nil
            ledger = ClaudeCodeUsageLedger()
            isScanning = false
            Task { await reader.reset() }
        }
    }

    func aggregate(_ bucket: Bucket, now: Date = Date(), calendar: Calendar = .current) -> ClaudeCodeUsageAggregate {
        let entries = ClaudeCodeUsageAggregate.entries(ledger.entries, in: bucket.interval(now: now, calendar: calendar))
        return ClaudeCodeUsageAggregate(entries: entries)
    }

    /// The popover's optional one-liner; nil until there is something to
    /// say today.
    func menuBarLine(now: Date = Date()) -> String? {
        guard enabled else { return nil }
        let today = aggregate(.today, now: now)
        guard today.messages > 0 else { return nil }
        let tokens = UsageFormatting.tokens(today.tokens.total)
        let cost = today.cost.map(UsageFormatting.usd) ?? "—"
        return String(localized: "Claude Code today: \(tokens) · ≈ \(cost)")
    }

    /// How far the pricing table is from Claude Code's own session totals,
    /// over the sessions where both exist and every model was priced —
    /// the early-warning that the table went stale. nil without data.
    var pricingDrift: (ours: Double, theirs: Double)? {
        let priced = Dictionary(grouping: ledger.entries, by: \.sessionID)
        var ours = 0.0, theirs = 0.0
        for (sessionID, total) in ledger.sessionTotals where !total.hasUnknownModelCost {
            guard let entries = priced[sessionID] else { continue }
            let costs = entries.compactMap(\.cost)
            guard costs.count == entries.count else { continue }
            ours += costs.reduce(0, +)
            theirs += total.totalCostUSD
        }
        guard theirs > 0 else { return nil }
        return (ours, theirs)
    }
}
#endif
