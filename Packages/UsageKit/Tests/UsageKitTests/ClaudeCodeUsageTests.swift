import XCTest
@testable import UsageKit

/// The fixtures under `Fixtures/claude-code/` are synthetic — same shape
/// as real logs (see `Scripts/probe-claude-code-logs.sh`), no content.
final class ClaudeCodeUsageTests: XCTestCase {
    private func fixtureRoot() throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "claude-code", withExtension: nil, subdirectory: "Fixtures"))
    }

    private func scratchRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: try fixtureRoot(), to: dir)
        return dir
    }

    // MARK: Pricing

    func testPricingMatchesWholeIdsAndDatedSnapshotsOnly() {
        XCTAssertEqual(ClaudeModelPricing.rates(for: "claude-opus-5-5")?.input, 4)
        XCTAssertEqual(ClaudeModelPricing.rates(for: "claude-opus-5")?.input, 5, "the shorter family, not the 5.5 prefix")
        XCTAssertEqual(ClaudeModelPricing.rates(for: "claude-haiku-4-5-20251001")?.input, 1, "dated snapshot")
        XCTAssertEqual(ClaudeModelPricing.rates(for: "claude-opus-4-5-20251101")?.output, 25)
        XCTAssertNil(ClaudeModelPricing.rates(for: "claude-opus-5-5-preview"), "a non-numeric suffix is not a snapshot")
        XCTAssertNil(ClaudeModelPricing.rates(for: "claude-unknown-9"))
        XCTAssertLessThan(ClaudeModelPricing.lastVerified, Date())
    }

    func testCostAddsEveryCategoryAtListPrice() {
        let tokens = ClaudeCodeTokenCounts(input: 1_000_000, output: 1_000_000, cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000, cacheRead: 1_000_000, webSearches: 1000)
        // Fable 5.1: 10 + 50 + 12.5 + 20 + 0.25 + 10 (searches)
        XCTAssertEqual(try XCTUnwrap(ClaudeModelPricing.cost(tokens, model: "claude-fable-5-1")), 102.75, accuracy: 0.0001)
        XCTAssertNil(ClaudeModelPricing.cost(tokens, model: "mystery"))
    }

    // MARK: Lines

    func testAssistantLineReadsOnlyUsageFields() throws {
        let line = #"{"type":"assistant","timestamp":"2026-10-01T10:00:05.123Z","requestId":"r","sessionId":"s","message":{"id":"m","model":"claude-opus-5-5","content":[{"type":"text","text":"secret"}],"usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":7,"cache_read_input_tokens":3,"output_tokens_details":{"thinking_tokens":1},"cache_creation":{"ephemeral_5m_input_tokens":4,"ephemeral_1h_input_tokens":3},"server_tool_use":{"web_search_requests":5}}}}"#
        guard case .assistant(let entry, let messageID, let requestID)? = ClaudeCodeLogLine.parse(Data(line.utf8), fallbackSessionID: "f") else {
            return XCTFail("expected an assistant line")
        }
        XCTAssertEqual(messageID, "m")
        XCTAssertEqual(requestID, "r")
        XCTAssertEqual(entry.sessionID, "s")
        XCTAssertEqual(entry.model, "claude-opus-5-5")
        XCTAssertEqual(entry.tokens, ClaudeCodeTokenCounts(input: 1, output: 2, thinking: 1, cacheWrite5m: 4, cacheWrite1h: 3, cacheRead: 3, webSearches: 5))
        XCTAssertEqual(entry.timestamp.timeIntervalSince1970, 1_790_848_805.123, accuracy: 0.001)

        let noSplit = #"{"type":"assistant","timestamp":"2026-10-01T10:00:05Z","message":{"id":"m2","model":"x","usage":{"input_tokens":1,"cache_creation_input_tokens":9}}}"#
        guard case .assistant(let plain, _, _)? = ClaudeCodeLogLine.parse(Data(noSplit.utf8), fallbackSessionID: "file-name") else {
            return XCTFail("expected an assistant line")
        }
        XCTAssertEqual(plain.tokens.cacheWrite5m, 9, "no 5m/1h split → all 5-minute writes")
        XCTAssertEqual(plain.sessionID, "file-name")

        XCTAssertNil(ClaudeCodeLogLine.parse(Data(#"{"type":"user","message":{"content":"x"}}"#.utf8), fallbackSessionID: "f"))
        XCTAssertNil(ClaudeCodeLogLine.parse(Data("garbage".utf8), fallbackSessionID: "f"))
        guard case .costState(let total)? = ClaudeCodeLogLine.parse(Data(#"{"type":"cost-state","sessionId":"s","totalCostUSD":2.5,"hasUnknownModelCost":true}"#.utf8), fallbackSessionID: "f") else {
            return XCTFail("expected cost-state")
        }
        XCTAssertEqual(total, ClaudeCodeSessionTotal(sessionID: "s", totalCostUSD: 2.5, hasUnknownModelCost: true))
    }

    // MARK: Reader

    func testScanDedupesRecursesAndKeepsTheLatestCostState() async throws {
        let root = try scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = root.appendingPathComponent("index.json")
        let reader = ClaudeCodeLogReader(root: root, indexURL: index)
        let ledger = await reader.scan()

        // msg_a counted once (duplicate line), msg_b, msg_c (subagent), msg_d (session-2); the partial line is skipped.
        XCTAssertEqual(ledger.entries.count, 4)
        XCTAssertEqual(Set(ledger.entries.map(\.sessionID)), ["session-1", "session-2"])
        XCTAssertEqual(ledger.entries.first { $0.model == "claude-unknown-9" }?.sessionID, "session-1", "subagent lines carry the parent's session")
        XCTAssertEqual(ledger.sessionTotals["session-1"]?.totalCostUSD, 1.25, "cumulative: the last record wins")
        XCTAssertEqual(ledger.files.count, 3)
        XCTAssertNotNil(ledger.lastScanned)
        XCTAssertTrue(FileManager.default.fileExists(atPath: index.path))

        let a = try XCTUnwrap(ledger.entries.first { $0.model == "claude-fable-5-1" })
        XCTAssertEqual(a.tokens, ClaudeCodeTokenCounts(input: 1000, output: 200, thinking: 50, cacheWrite5m: 300, cacheWrite1h: 200, cacheRead: 4000, webSearches: 2))
    }

    func testScanIsIncrementalAndRecoversFromTruncation() async throws {
        let root = try scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = root.appendingPathComponent("index.json")
        let file = root.appendingPathComponent("project-a/session-2.jsonl")
        let reader = ClaudeCodeLogReader(root: root, indexURL: index)
        _ = await reader.scan()

        // Finish the partial line, append one more message.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((#","output_tokens":5}}}"# + "\n").utf8))
        try handle.write(contentsOf: Data((#"{"type":"assistant","timestamp":"2026-09-15T09:00:00.000Z","requestId":"req_e","message":{"id":"msg_e","model":"claude-opus-5-5","usage":{"input_tokens":1,"output_tokens":1}}}"# + "\n").utf8))
        try handle.close()
        let second = await reader.scan()
        XCTAssertEqual(second.entries.count, 6, "the completed partial line and the new one")
        XCTAssertEqual(second.entries.filter { $0.sessionID == "session-2" }.count, 3)

        // A fresh reader over the same index continues where this one left off.
        let resumed = ClaudeCodeLogReader(root: root, indexURL: index)
        let third = await resumed.scan()
        XCTAssertEqual(third.entries.count, 6, "nothing re-counted")

        // Truncate the file: it is re-read from zero, dedupe keeps the count.
        try Data((#"{"type":"assistant","timestamp":"2026-09-16T09:00:00.000Z","requestId":"req_f","message":{"id":"msg_f","model":"claude-opus-5-5","usage":{"input_tokens":1,"output_tokens":1}}}"# + "\n").utf8).write(to: file)
        let fourth = await resumed.scan()
        XCTAssertEqual(fourth.entries.count, 7)
        XCTAssertEqual(fourth.files[file.resolvingSymlinksInPath().path]?.bytesParsed, try Data(contentsOf: file).count)

        await resumed.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: index.path))
        let afterReset = await resumed.currentLedger()
        XCTAssertTrue(afterReset.entries.isEmpty)
    }

    // MARK: Aggregates

    func testAggregateBucketsAndPerModelCosts() async throws {
        let root = try scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ledger = await ClaudeCodeLogReader(root: root, indexURL: root.appendingPathComponent("i.json")).scan()

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        utc.firstWeekday = 2 // Monday
        let now = ISO8601DateFormatter().date(from: "2026-10-02T12:00:00Z")!

        let all = ClaudeCodeUsageAggregate(entries: ledger.entries)
        XCTAssertEqual(all.messages, 4)
        XCTAssertEqual(all.sessions, 2)
        XCTAssertTrue(all.hasUnpricedModels, "claude-unknown-9")
        XCTAssertEqual(all.byModel.first?.model, "claude-fable-5-1", "most tokens first")
        let fable = try XCTUnwrap(all.byModel.first)
        // 1000×10 + 200×50 + 300×12.5 + 200×20 + 4000×0.25 per MTok + 2 searches × $0.01
        XCTAssertEqual(try XCTUnwrap(fable.cost), (10_000 + 10_000 + 3_750 + 4_000 + 1_000) / 1_000_000 + 0.02, accuracy: 1e-9)
        XCTAssertNil(all.byModel.first { $0.model == "claude-unknown-9" }?.cost)
        XCTAssertNotNil(all.cost, "priced models still sum")

        let today = ClaudeCodeUsageAggregate(entries: ClaudeCodeUsageAggregate.entries(ledger.entries, in: ClaudeCodeUsageAggregate.today(now: now, calendar: utc)))
        XCTAssertEqual(today.messages, 1, "only the 01:00 subagent message is on Oct 2 UTC")
        let week = ClaudeCodeUsageAggregate(entries: ClaudeCodeUsageAggregate.entries(ledger.entries, in: ClaudeCodeUsageAggregate.last(days: 7, now: now)))
        XCTAssertEqual(week.messages, 3, "Sep 25 12:00 → Oct 2 12:00: the three October messages")
        let month = ClaudeCodeUsageAggregate(entries: ClaudeCodeUsageAggregate.entries(ledger.entries, in: ClaudeCodeUsageAggregate.last(days: 30, now: now)))
        XCTAssertEqual(month.messages, 4, "Sep 2 → Oct 2: Sep 15 is in too — rolling windows nest, so the month row never reads smaller than the week row")

        // Time zones move the day boundary: at UTC-6, the 23:30Z message is still Oct 1 local.
        var mexico = utc
        mexico.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let localToday = ClaudeCodeUsageAggregate(entries: ClaudeCodeUsageAggregate.entries(ledger.entries, in: ClaudeCodeUsageAggregate.today(now: now, calendar: mexico)))
        XCTAssertEqual(localToday.messages, 0, "01:00Z on Oct 2 is 19:00 Oct 1 in Mexico City")
    }
}
