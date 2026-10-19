import XCTest
import UniformTypeIdentifiers
#if os(iOS)
import CoreTransferable
#endif
import UsageKit
@testable import AIMeter

final class UsageExportTests: XCTestCase {
    private let exportedAt = Date(timeIntervalSince1970: 1_792_958_400) // 2026-10-25 20:00 UTC

    private func sample(_ offset: TimeInterval, _ used: Double, resetsIn: TimeInterval? = 3600) -> TimelineSample {
        let timestamp = exportedAt.addingTimeInterval(offset)
        return TimelineSample(timestamp: timestamp, usedPct: used, resetsAt: resetsIn.map { timestamp.addingTimeInterval($0) })
    }

    private var export: UsageExport {
        UsageExport(
            accounts: [
                UsageExport.Account(
                    name: "Work, Inc",
                    providerID: "claude",
                    history: [
                        "weekly": [sample(-7200, 61)],
                        "model.Top": [sample(-7200, 9.5)],
                        "session": [sample(-7200, 40), sample(-3600, 42.25, resetsIn: nil)],
                    ],
                    latest: UsageSnapshot(
                        providerID: "claude", planName: "max", fetchedAt: exportedAt.addingTimeInterval(-3600),
                        windows: [UsageWindow(kind: .session, usedPct: 42.25, resetsAt: nil, severity: .warning)],
                        spend: SpendStatus(enabled: true, percent: 31, usedAmount: 7.75, limitAmount: 25, currency: "USD")
                    )
                ),
                UsageExport.Account(name: "Personal", providerID: "claude", history: [:], latest: nil),
            ],
            exportedAt: exportedAt
        )
    }

    func testTheCSVHasOneRowPerSampleInTheAppsOrder() {
        let lines = export.csv().split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "account,provider,window,timestamp,used_pct,resets_at")
        XCTAssertEqual(lines.count, 5)
        // Session before weekly before the model, samples in time order,
        // the name with a comma quoted, numbers with a point, dates ISO 8601.
        XCTAssertEqual(lines[1], "\"Work, Inc\",claude,session,2026-10-25T18:00:00Z,40,2026-10-25T19:00:00Z")
        XCTAssertEqual(lines[2], "\"Work, Inc\",claude,session,2026-10-25T19:00:00Z,42.25,")
        XCTAssertEqual(lines[3], "\"Work, Inc\",claude,weekly,2026-10-25T18:00:00Z,61,2026-10-25T19:00:00Z")
        XCTAssertEqual(lines[4], "\"Work, Inc\",claude,model.Top,2026-10-25T18:00:00Z,9.5,2026-10-25T19:00:00Z")
    }

    func testCSVFieldsAndNumbers() {
        XCTAssertEqual(UsageExport.field("Personal"), "Personal")
        XCTAssertEqual(UsageExport.field("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(UsageExport.number(100), "100")
        XCTAssertEqual(UsageExport.number(42.5), "42.5")
        XCTAssertEqual(UsageExport.number(42.257), "42.26")
        XCTAssertEqual(UsageExport.orderedKeys(["credits", "model.B", "weekly", "model.A", "session", "odd"]),
                       ["session", "weekly", "model.A", "model.B", "credits", "odd"])
    }

    func testTheJSONCarriesHistoryAndTheLatestSnapshot() throws {
        let data = try export.json()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["app"] as? String, "AIMeter")
        XCTAssertEqual(object["format"] as? Int, UsageExport.formatVersion)
        XCTAssertEqual(object["exportedAt"] as? String, "2026-10-25T20:00:00Z")

        let accounts = try XCTUnwrap(object["accounts"] as? [[String: Any]])
        XCTAssertEqual(accounts.map { $0["name"] as? String }, ["Work, Inc", "Personal"])
        let history = try XCTUnwrap(accounts[0]["history"] as? [String: [[String: Any]]])
        XCTAssertEqual(history["session"]?.count, 2)
        XCTAssertEqual(history["session"]?[1]["usedPct"] as? Double, 42.25)
        XCTAssertNil(history["session"]?[1]["resetsAt"])
        let latest = try XCTUnwrap(accounts[0]["latest"] as? [String: Any])
        XCTAssertEqual(latest["plan"] as? String, "max")
        XCTAssertEqual((latest["windows"] as? [[String: Any]])?.first?["severity"] as? String, "warning")
        XCTAssertEqual((latest["spend"] as? [String: Any])?["currency"] as? String, "USD")
        XCTAssertNil(accounts[1]["latest"] as? [String: Any])
    }

    func testTheFileNameCarriesTheDay() {
        XCTAssertEqual(export.fileName(.csv), "AIMeter usage \(Self.day(of: exportedAt)).csv")
        XCTAssertEqual(export.fileName(.json).hasSuffix(".json"), true)
    }

    #if os(iOS)
    /// What the share sheet receives from each item is the file itself.
    func testTheShareItemsExportTheirFiles() async throws {
        // `exported(as:)` is the test's own tool, not the app's: the share
        // sheet does this itself on every iOS the app runs on.
        guard #available(iOS 18.2, *) else { throw XCTSkip("exported(as:) needs iOS 18.2") }
        let csvData = try await UsageExportCSV(export: export).exported(as: .commaSeparatedText)
        XCTAssertEqual(String(decoding: csvData, as: UTF8.self), export.csv())
        let jsonData = try await UsageExportJSON(export: export).exported(as: .json)
        XCTAssertEqual(jsonData, try export.json())
    }
    #endif

    /// The day in the user's calendar, as the export names it.
    private static func day(of date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
