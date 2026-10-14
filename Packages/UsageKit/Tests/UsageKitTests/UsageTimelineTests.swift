import XCTest
@testable import UsageKit

final class UsageTimelineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// `resetsIn` is measured from `t0`, not from the sample: one window's
    /// samples all carry the same boundary.
    private func sample(_ minutes: Double, used: Double, resetsIn: TimeInterval? = 5 * 3600) -> TimelineSample {
        TimelineSample(timestamp: t0.addingTimeInterval(minutes * 60), usedPct: used, resetsAt: resetsIn.map { t0.addingTimeInterval($0) })
    }

    // MARK: Reset detection

    func testADropPastTheThresholdIsAReset() {
        let fixed = t0.addingTimeInterval(5 * 3600)
        let a = TimelineSample(timestamp: t0, usedPct: 42, resetsAt: fixed)
        let b = TimelineSample(timestamp: t0.addingTimeInterval(1800), usedPct: 30, resetsAt: fixed)
        XCTAssertTrue(UsageTimeline.isReset(from: a, to: b))
        let c = TimelineSample(timestamp: t0.addingTimeInterval(1800), usedPct: 35, resetsAt: fixed)
        XCTAssertFalse(UsageTimeline.isReset(from: a, to: c), "a 7-point fall is noise, not a reset")
    }

    func testAResetDateMovingOnIsAResetEvenWithoutADrop() {
        let a = TimelineSample(timestamp: t0, usedPct: 3, resetsAt: t0.addingTimeInterval(3600))
        let b = TimelineSample(timestamp: t0.addingTimeInterval(1800), usedPct: 2, resetsAt: t0.addingTimeInterval(6 * 3600))
        XCTAssertTrue(UsageTimeline.isReset(from: a, to: b))
        let jitter = TimelineSample(timestamp: t0.addingTimeInterval(1800), usedPct: 5, resetsAt: t0.addingTimeInterval(3600 + 0.5))
        XCTAssertFalse(UsageTimeline.isReset(from: a, to: jitter), "microsecond jitter on one boundary is not a new window")
        let nilDates = TimelineSample(timestamp: t0, usedPct: 10, resetsAt: nil)
        XCTAssertFalse(UsageTimeline.isReset(from: nilDates, to: TimelineSample(timestamp: t0, usedPct: 12, resetsAt: nil)))
    }

    func testIndicesAndSegments() {
        let series = [
            sample(0, used: 10), sample(30, used: 40), sample(60, used: 70),
            sample(90, used: 5), sample(120, used: 20),
            sample(150, used: 2, resetsIn: 10 * 3600),
        ]
        XCTAssertEqual(UsageTimeline.resetIndices(in: series), [3, 5])
        XCTAssertEqual(UsageTimeline.segments(series).map(\.count), [3, 2, 1])
        XCTAssertEqual(UsageTimeline.resetIndices(in: []), [])
        XCTAssertEqual(UsageTimeline.segments([]).count, 0)
    }

    // MARK: Compaction

    func testCompactionKeepsRawRecentThinsOldAndDropsExpired() {
        let now = t0
        let hour: TimeInterval = 3600
        var series: [TimelineSample] = []
        // 31 days ago: expired.
        series.append(TimelineSample(timestamp: now.addingTimeInterval(-31 * 24 * hour), usedPct: 50, resetsAt: nil))
        // 3 days ago, four samples in one hour: thinned to the highest.
        let old = now.addingTimeInterval(-3 * 24 * hour)
        let oldBucket = floor(old.timeIntervalSince1970 / hour) * hour
        for (offset, used) in [(0.0, 10.0), (600, 30), (1200, 25), (1800, 12)] {
            series.append(TimelineSample(timestamp: Date(timeIntervalSince1970: oldBucket + offset), usedPct: used, resetsAt: nil))
        }
        // Within 48 h: kept as is.
        series.append(TimelineSample(timestamp: now.addingTimeInterval(-hour), usedPct: 41, resetsAt: nil))
        series.append(TimelineSample(timestamp: now.addingTimeInterval(-1800), usedPct: 43, resetsAt: nil))

        let kept = UsageTimeline.compacted(series, now: now, rawWindow: UsageTimelineStore.rawWindow, retention: UsageTimelineStore.retention)
        XCTAssertEqual(kept.map(\.usedPct), [30, 41, 43])
        XCTAssertEqual(kept.first?.timestamp, Date(timeIntervalSince1970: oldBucket + 600), "the peak sample itself survives")
    }

    // MARK: One sample per refresh

    func testTheSameRefreshReplacesTheLastSampleInsteadOfAppending() {
        let series = [sample(0, used: 40), sample(30, used: 50)]
        let again = TimelineSample(timestamp: t0.addingTimeInterval(30 * 60 + 1), usedPct: 51, resetsAt: series[1].resetsAt)
        XCTAssertEqual(UsageTimeline.appending(again, to: series), [series[0], again], "the app and the widget, a second apart")
        let next = sample(60, used: 55)
        XCTAssertEqual(UsageTimeline.appending(next, to: series), series + [next])
        XCTAssertEqual(UsageTimeline.appending(next, to: []), [next])
    }

    func testDeduplicatedKeepsTheLaterOfOneRefreshRecordedTwice() {
        let a = sample(0, used: 40), b = sample(30, used: 50), c = sample(60, used: 55)
        let sameSecond = TimelineSample(timestamp: b.timestamp, usedPct: 50, resetsAt: b.resetsAt)
        let secondLater = TimelineSample(timestamp: b.timestamp.addingTimeInterval(1), usedPct: 50, resetsAt: b.resetsAt)
        XCTAssertEqual(UsageTimeline.deduplicated([a, b, sameSecond, c]), [a, sameSecond, c])
        XCTAssertEqual(UsageTimeline.deduplicated([a, b, secondLater, c]), [a, secondLater, c])
        XCTAssertEqual(UsageTimeline.deduplicated([a, b, c]), [a, b, c], "half an hour apart is two refreshes")
        XCTAssertEqual(UsageTimeline.deduplicated([]), [])
    }

    // MARK: Store

    func testStoreKeepsOneSamplePerRefresh() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("timeline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UsageTimelineStore(directory: directory)
        let snapshot = UsageSnapshot(providerID: "p", planName: nil, fetchedAt: t0, windows: [
            UsageWindow(kind: .weekly, usedPct: 95, resetsAt: nil),
        ])
        store.record(snapshot, for: "acc", at: t0)
        store.record(snapshot, for: "acc", at: t0.addingTimeInterval(0.4))
        store.record(snapshot, for: "acc", at: t0.addingTimeInterval(1800))
        let weekly = store.samples(for: "acc", kind: .weekly)
        XCTAssertEqual(weekly.count, 2, "the widget's copy of the app's refresh is not a second point")
        XCTAssertEqual(Set(weekly.map(\.timestamp)).count, 2)
    }

    func testStoreRecordsPerKindAndClears() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("timeline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UsageTimelineStore(directory: directory)
        XCTAssertTrue(store.samples(for: "acc", kind: .session).isEmpty)

        let reset = t0.addingTimeInterval(3 * 3600)
        let first = UsageSnapshot(providerID: "p", planName: nil, fetchedAt: t0, windows: [
            UsageWindow(kind: .session, usedPct: 20, resetsAt: reset),
            UsageWindow(kind: .weekly, usedPct: 55, resetsAt: nil),
        ])
        store.record(first, for: "acc", at: t0)
        store.record(first, for: "acc", at: t0.addingTimeInterval(1800))

        let session = store.samples(for: "acc", kind: .session)
        XCTAssertEqual(session.map(\.usedPct), [20, 20])
        XCTAssertEqual(session.first?.resetsAt, reset)
        XCTAssertEqual(store.samples(for: "acc", kind: .weekly).count, 2)
        XCTAssertEqual(store.samples(for: "acc", kind: .session, since: t0.addingTimeInterval(1)).count, 1)
        XCTAssertEqual(Set(store.allSamples(for: "acc").keys), ["session", "weekly"])
        XCTAssertTrue(store.samples(for: "other", kind: .session).isEmpty, "keyed per account")

        store.clear(for: "acc")
        XCTAssertTrue(store.samples(for: "acc", kind: .session).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("acc.json").path))
    }

    func testDamagedFileStartsOver() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("timeline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("<not json>".utf8).write(to: directory.appendingPathComponent("acc.json"))
        let store = UsageTimelineStore(directory: directory)
        XCTAssertTrue(store.samples(for: "acc", kind: .session).isEmpty)
        store.record(UsageSnapshot(providerID: "p", planName: nil, fetchedAt: t0, windows: [UsageWindow(kind: .session, usedPct: 1, resetsAt: nil)]), for: "acc", at: t0)
        XCTAssertEqual(store.samples(for: "acc", kind: .session).count, 1)
    }
}
