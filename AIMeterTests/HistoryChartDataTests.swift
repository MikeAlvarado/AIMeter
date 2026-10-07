import XCTest
import UsageKit
@testable import AIMeter

final class HistoryChartDataTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(hoursAgo: Double, used: Double, resetsAt: Date? = nil) -> TimelineSample {
        TimelineSample(timestamp: now.addingTimeInterval(-hoursAgo * 3600), usedPct: used, resetsAt: resetsAt)
    }

    func testNotReadyUntilAnHourOfSamples() {
        XCTAssertFalse(HistoryChartData(samples: [], range: .day, now: now).isReady)
        XCTAssertNil(HistoryChartData(samples: [], range: .day, now: now).recordingSince)

        let one = HistoryChartData(samples: [sample(hoursAgo: 0.5, used: 10)], range: .day, now: now)
        XCTAssertFalse(one.isReady)
        XCTAssertEqual(one.recordingSince, now.addingTimeInterval(-1800))

        let close = HistoryChartData(samples: [sample(hoursAgo: 0.5, used: 10), sample(hoursAgo: 0.1, used: 12)], range: .day, now: now)
        XCTAssertFalse(close.isReady, "two samples 24 minutes apart")

        let ready = HistoryChartData(samples: [sample(hoursAgo: 1.5, used: 10), sample(hoursAgo: 0.1, used: 12)], range: .day, now: now)
        XCTAssertTrue(ready.isReady)
        XCTAssertFalse(ready.showsSparkline, "a sparkline wants three points")
    }

    func testPointsAreClippedToTheRangeAndSplitAtResets() {
        let fixed = now.addingTimeInterval(3600)
        let later = now.addingTimeInterval(6 * 3600)
        let samples = [
            sample(hoursAgo: 30, used: 50, resetsAt: fixed),   // outside a 24 h range
            sample(hoursAgo: 20, used: 30, resetsAt: fixed),
            sample(hoursAgo: 15, used: 70, resetsAt: fixed),
            sample(hoursAgo: 10, used: 5, resetsAt: later),    // reset: date moved on and figure fell
            sample(hoursAgo: 5, used: 40, resetsAt: later),
            sample(hoursAgo: 1, used: 45, resetsAt: later),
        ]
        let day = HistoryChartData(samples: samples, range: .day, now: now)
        XCTAssertEqual(day.points.map(\.usedPct), [30, 70, 5, 40, 45])
        XCTAssertEqual(day.points.map(\.segment), [0, 0, 1, 1, 1])
        XCTAssertEqual(day.resets, [now.addingTimeInterval(-10 * 3600)])
        XCTAssertEqual(day.peak?.usedPct, 70)
        XCTAssertEqual(day.recordingSince, samples.first?.timestamp, "oldest on record, not oldest in range")
        XCTAssertTrue(day.showsSparkline)
        XCTAssertEqual(day.start, now.addingTimeInterval(-24 * 3600))
        XCTAssertEqual(day.end, now)

        let week = HistoryChartData(samples: samples, range: .week, now: now)
        XCTAssertEqual(week.points.count, 6)
    }

    func testSummarySpeaksSpanPeakAndResets() {
        let samples = [sample(hoursAgo: 5, used: 20), sample(hoursAgo: 3, used: 82), sample(hoursAgo: 1, used: 2)]
        let data = HistoryChartData(samples: samples, range: .day, now: now)
        let text = data.summary(for: .session)
        XCTAssertTrue(text.contains("5-hour session"), text)
        XCTAssertTrue(text.contains("last 24 hours"), text)
        XCTAssertTrue(text.contains("82%"), text)
        XCTAssertTrue(text.contains("Reset once"), text)

        let quiet = HistoryChartData(samples: [sample(hoursAgo: 5, used: 20), sample(hoursAgo: 1, used: 30)], range: .week, now: now)
        XCTAssertTrue(quiet.summary(for: .weekly).contains("No resets"))
    }

    func testDemoTimelineEndsOnTheSnapshotAndHasResets() {
        let timeline = DemoUsageData.timeline(now: now)
        let snapshot = DemoUsageData.snapshot(now: now)
        for window in snapshot.windows {
            let series = try? XCTUnwrap(timeline[window.kind.storageKey])
            XCTAssertEqual(series?.last?.usedPct, window.usedPct, "\(window.kind)")
            XCTAssertEqual(series?.last?.timestamp, now)
            XCTAssertGreaterThan(series?.count ?? 0, 1400, "30 days every 30 minutes")
        }
        let sessions = HistoryChartData(samples: timeline["session"] ?? [], range: .week, now: now)
        XCTAssertGreaterThan(sessions.resets.count, 20, "about 33 five-hour cycles in a week")
        XCTAssertEqual(HistoryChartData(samples: timeline["weekly"] ?? [], range: .week, now: now).resets.count, 1)
        XCTAssertEqual(HistoryChartData(samples: timeline["weekly"] ?? [], range: .month, now: now).resets.count, 4, "one weekly reset per week over 30 days")
        XCTAssertTrue(sessions.isReady)
        XCTAssertLessThanOrEqual(sessions.peak?.usedPct ?? 101, 100)
    }

    func testSecondDemoTimelineEndsOnItsOwnSnapshot() {
        let snapshot = DemoUsageData.secondSnapshot(now: now)
        let timeline = DemoUsageData.timeline(now: now, for: snapshot)
        for window in snapshot.windows {
            XCTAssertEqual(timeline[window.kind.storageKey]?.last?.usedPct, window.usedPct, "\(window.kind)")
        }
        XCTAssertNil(timeline["model.Top model"], "no per-model window, no per-model series")
        XCTAssertEqual(DemoUsageData.accounts(now: now).map(\.account.displayName), ["Personal", "Work"])
    }
}
