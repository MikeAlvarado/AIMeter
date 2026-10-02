#if os(macOS)
import XCTest
import UsageKit
@testable import AIMeter

/// `ClaudeCodeUsageModel` over a scratch logs folder and index — enable,
/// scan, buckets, the popover line, and that off forgets the index.
final class ClaudeCodeUsageModelTests: XCTestCase {
    private var root: URL!
    private var index: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cc-model-\(UUID().uuidString)", isDirectory: true)
        index = root.appendingPathComponent("index/claude-code-usage.json")
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = ISO8601DateFormatter().string(from: Date())
        let line = #"{"type":"assistant","timestamp":"\#(now)","requestId":"r1","sessionId":"s1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":250000,"output_tokens":50000}}}"#
        try (line + "\n").write(to: project.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testDisabledReadsNothing() async {
        let model = ClaudeCodeUsageModel(root: root, indexURL: index, enabled: false)
        XCTAssertTrue(model.logsExist)
        model.rescanIfEnabled()
        XCTAssertNil(model.menuBarLine())
        XCTAssertEqual(model.aggregate(.all).messages, 0)
    }

    func testEnabledScansBucketsAndFormatsTheLine() async {
        let model = ClaudeCodeUsageModel(root: root, indexURL: index, enabled: true)
        await model.scan()
        XCTAssertEqual(model.aggregate(.today).messages, 1)
        XCTAssertEqual(model.aggregate(.all).tokens.total, 300_000)
        // 250k × $4 + 50k × $20 per MTok = $1 + $1
        XCTAssertEqual(try XCTUnwrap(model.aggregate(.all).cost), 2.0, accuracy: 1e-9)
        XCTAssertEqual(model.menuBarLine(), "Claude Code today: 300K · ≈ $2.00")
        XCTAssertTrue(FileManager.default.fileExists(atPath: index.path))
        XCTAssertNil(model.pricingDrift, "no cost-state in the log")

        model.setEnabled(false)
        XCTAssertNil(model.menuBarLine())
        XCTAssertEqual(model.aggregate(.all).messages, 0)
        // The reset lands on the reader's executor; give it a moment.
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(FileManager.default.fileExists(atPath: index.path), "off forgets the index")
    }

    func testTokenFormatting() {
        XCTAssertEqual(UsageFormatting.tokens(840), "840")
        XCTAssertEqual(UsageFormatting.tokens(9_999), "9,999")
        XCTAssertEqual(UsageFormatting.tokens(12_345), "12.3K")
        XCTAssertEqual(UsageFormatting.tokens(300_000), "300K")
        XCTAssertEqual(UsageFormatting.tokens(1_234_567), "1.2M")
        XCTAssertEqual(UsageFormatting.tokens(2_000_000_000), "2B")
        XCTAssertEqual(UsageFormatting.usd(4.1), "$4.10")
    }
}
#endif
