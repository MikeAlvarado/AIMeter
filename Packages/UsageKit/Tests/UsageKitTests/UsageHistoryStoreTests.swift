import XCTest
@testable import UsageKit

final class UsageHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "UsageHistoryStoreTests"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func snapshot(_ used: Double, resetsAt: Date) -> UsageSnapshot {
        UsageSnapshot(providerID: "claude", windows: [
            UsageWindow(kind: .session, usedPct: used, resetsAt: resetsAt),
        ])
    }

    func testAppendsSamplesInOrder() {
        let store = UsageHistoryStore(userDefaults: defaults)
        store.record(snapshot(10, resetsAt: now.addingTimeInterval(3600)), at: now)
        store.record(snapshot(20, resetsAt: now.addingTimeInterval(3600)), at: now.addingTimeInterval(600))

        let samples = store.samples(for: "claude", kind: .session)
        XCTAssertEqual(samples.map(\.usedPct), [10, 20])
        XCTAssertEqual(samples[0].timestamp, now)
    }

    func testResetDropDiscardsPriorSamples() {
        let store = UsageHistoryStore(userDefaults: defaults)
        store.record(snapshot(80, resetsAt: now.addingTimeInterval(3600)), at: now)
        // Big drop → new window → prior samples discarded, only the new one.
        store.record(snapshot(5, resetsAt: now.addingTimeInterval(5 * 3600)), at: now.addingTimeInterval(600))

        let samples = store.samples(for: "claude", kind: .session)
        XCTAssertEqual(samples.map(\.usedPct), [5])
    }

    func testSmallDecreaseWithinToleranceKeepsHistory() {
        let store = UsageHistoryStore(userDefaults: defaults)
        store.record(snapshot(50, resetsAt: now.addingTimeInterval(3600)), at: now)
        // −4 is under the 10-point reset threshold: kept (noise, not a reset).
        store.record(snapshot(46, resetsAt: now.addingTimeInterval(3600)), at: now.addingTimeInterval(600))

        XCTAssertEqual(store.samples(for: "claude", kind: .session).map(\.usedPct), [50, 46])
    }

    func testBoundedToMaxSamples() {
        let store = UsageHistoryStore(userDefaults: defaults)
        let cap = UsageHistoryStore.maxSamplesPerKind
        for i in 0..<(cap + 10) {
            let used = Double(min(90, i)) // monotonic-ish, no reset drop
            store.record(snapshot(used, resetsAt: now.addingTimeInterval(3600)),
                         at: now.addingTimeInterval(Double(i) * 60))
        }
        XCTAssertEqual(store.samples(for: "claude", kind: .session).count, cap)
    }

    func testScopedPerProviderAndCleared() {
        let store = UsageHistoryStore(userDefaults: defaults)
        store.record(snapshot(10, resetsAt: now.addingTimeInterval(3600)), at: now)
        XCTAssertEqual(store.samples(for: "claude", kind: .session).count, 1)
        XCTAssertTrue(store.samples(for: "openai", kind: .session).isEmpty)

        store.clear(for: "claude")
        XCTAssertTrue(store.samples(for: "claude", kind: .session).isEmpty)
    }

    func testObservingSinceSetOnceAndSurvivesResets() {
        let store = UsageHistoryStore(userDefaults: defaults)
        XCTAssertNil(store.observingSince(for: "claude"))

        store.record(snapshot(10, resetsAt: now.addingTimeInterval(3600)), at: now)
        XCTAssertEqual(store.observingSince(for: "claude"), now)

        // A later reset discards samples but must NOT move the observing-since.
        store.record(snapshot(80, resetsAt: now.addingTimeInterval(3600)), at: now.addingTimeInterval(600))
        store.record(snapshot(5, resetsAt: now.addingTimeInterval(5 * 3600)), at: now.addingTimeInterval(1200))
        XCTAssertEqual(store.observingSince(for: "claude"), now)

        store.clear(for: "claude")
        XCTAssertNil(store.observingSince(for: "claude"))
    }
}
