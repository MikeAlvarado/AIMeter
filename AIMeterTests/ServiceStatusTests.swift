import XCTest
import UsageKit
@testable import AIMeter

/// Service status as the model and the surfaces see it: the throttle, the
/// aging rule, what the banner and the footer line key on. No network —
/// the one source used here is a stub injected through
/// `serviceStatusSources`.
final class ServiceStatusTests: XCTestCase {
    private var scratch: ScratchDefaults!
    private var registry: AccountRegistryStore!

    override func setUp() {
        scratch = ScratchDefaults()
        registry = AccountRegistryStore(userDefaults: scratch.defaults)
        registry.add(.managed("acc-work", name: "Work"))
        registry.add(.managed("acc-home", name: "Home"))
    }

    override func tearDown() {
        scratch.wipe()
    }

    private func makeModel() -> UsageModel {
        UsageModel(registry: registry, platformServices: false)
    }

    private func degraded(_ indicator: ServiceStatus.Indicator = .major, checkedAt: Date = Date()) -> ServiceStatus {
        ServiceStatus(indicator: indicator, description: "Partial System Outage",
                      affectedComponents: ["claude.ai"], incidentTitle: "Elevated errors", checkedAt: checkedAt)
    }

    private var providerID: String { ProviderCatalog.defaultProviderID }

    // MARK: Throttle

    func testCheckIsDueOnFirstRunAndAfterTheInterval() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(UsageModel.isServiceStatusDue(lastChecked: nil, now: now))
        XCTAssertFalse(UsageModel.isServiceStatusDue(lastChecked: now.addingTimeInterval(-4 * 60), now: now))
        XCTAssertTrue(UsageModel.isServiceStatusDue(lastChecked: now.addingTimeInterval(-5 * 60), now: now))
    }

    func testRefreshChecksOncePerProviderAndThrottles() async {
        let model = makeModel()
        let source = StubStatusSource(status: degraded())
        model.serviceStatusSources[providerID] = source
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        await model.refreshServiceStatus(now: t0)
        XCTAssertEqual(source.calls, 1, "two accounts of one family share one check")
        XCTAssertEqual(model.serviceStatus[providerID]?.indicator, .major)

        await model.refreshServiceStatus(now: t0.addingTimeInterval(60))
        XCTAssertEqual(source.calls, 1, "within the floor")

        await model.refreshServiceStatus(now: t0.addingTimeInterval(6 * 60))
        XCTAssertEqual(source.calls, 2)
    }

    func testRefreshIsANoOpWhenDisabledOrInDemo() async {
        let model = makeModel()
        let source = StubStatusSource(status: degraded())
        model.serviceStatusSources[providerID] = source

        model.setChecksServiceStatus(false)
        await model.refreshServiceStatus()
        XCTAssertEqual(source.calls, 0)

        model.setChecksServiceStatus(true)
        model.enterDemoMode()
        await model.refreshServiceStatus()
        XCTAssertEqual(source.calls, 0)
        XCTAssertNil(model.activeIncident)
    }

    // MARK: Aging

    func testFailedCheckKeepsAFreshStatusAndDropsAStaleOne() {
        let model = makeModel()
        let now = Date()
        model.apply(degraded(checkedAt: now.addingTimeInterval(-10 * 60)), for: providerID, now: now)
        model.apply(nil, for: providerID, now: now)
        XCTAssertNotNil(model.serviceStatus[providerID], "10 minutes old: still trusted")

        model.apply(nil, for: providerID, now: now.addingTimeInterval(31 * 60))
        XCTAssertNil(model.serviceStatus[providerID], "past 30 minutes without confirmation: gone")
    }

    func testTurningTheCheckOffClearsWhatIsShown() {
        let model = makeModel()
        model.apply(degraded(), for: providerID, now: Date())
        XCTAssertNotNil(model.activeIncident)
        model.setChecksServiceStatus(false)
        XCTAssertNil(model.activeIncident)
        XCTAssertTrue(model.serviceStatus.isEmpty)
    }

    // MARK: Banner

    func testBannerOnlyForADegradedStatus() {
        let model = makeModel()
        XCTAssertNil(model.activeIncident)

        model.serviceStatus[providerID] = ServiceStatus(indicator: .operational, description: "All Systems Operational")
        XCTAssertNil(model.activeIncident)

        model.serviceStatus[providerID] = ServiceStatus(indicator: .unknown, description: "?")
        XCTAssertNil(model.activeIncident, "unknown is never announced")

        for indicator in [ServiceStatus.Indicator.minor, .major, .critical, .maintenance] {
            model.serviceStatus[providerID] = degraded(indicator)
            XCTAssertEqual(model.activeIncident?.status.indicator, indicator)
            XCTAssertEqual(model.activeIncident?.providerID, providerID)
        }
    }

    func testBannerPicksTheMostSevereProvider() {
        let model = makeModel()
        model.serviceStatus[providerID] = degraded(.minor)
        model.serviceStatus["other"] = degraded(.critical)
        XCTAssertEqual(model.activeIncident?.providerID, "other")
    }

    // MARK: Footer line and footnote

    func testIncidentNoteNeedsAFailingAccountAndADegradedProvider() {
        let model = makeModel()
        var usage = model.accounts[0]
        XCTAssertNil(model.incidentNote(for: usage), "no error, no status")

        usage.lastError = "HTTP 503"
        XCTAssertNil(model.incidentNote(for: usage), "error but the provider is fine")

        model.serviceStatus[providerID] = degraded()
        let note = try? XCTUnwrap(model.incidentNote(for: usage))
        XCTAssertEqual(note, "\(ProviderCatalog.displayName(for: providerID)) reports an incident: Elevated errors")

        usage.isOffline = true
        XCTAssertNil(model.incidentNote(for: usage), "the device's network, not their outage")
        usage.isOffline = false

        usage.needsReauthentication = true
        XCTAssertNil(model.incidentNote(for: usage), "an incident doesn't invalidate a login")
        usage.needsReauthentication = false

        usage.lastError = nil
        XCTAssertNil(model.incidentNote(for: usage))
    }

    func testFootnoteShowsTheDescriptionAndFreshness() {
        let model = makeModel()
        XCTAssertNil(model.serviceStatusFootnote(for: providerID))
        let now = Date()
        model.serviceStatus[providerID] = ServiceStatus(indicator: .operational, description: "All Systems Operational",
                                                        checkedAt: now.addingTimeInterval(-3 * 60))
        let note = try? XCTUnwrap(model.serviceStatusFootnote(for: providerID, now: now))
        XCTAssertTrue(note?.contains("All Systems Operational") == true, "\(note ?? "")")
        XCTAssertTrue(note?.contains("3") == true, "carries the age: \(note ?? "")")
    }

    // MARK: Catalog

    func testCatalogResolvesTheClaudeStatusPage() {
        XCTAssertTrue(ProviderCatalog.statusSource(for: providerID) is ClaudeStatusSource)
        XCTAssertEqual(ProviderCatalog.statusPageURL(for: providerID), ClaudeStatusSource.pageURL)
        XCTAssertNil(ProviderCatalog.statusSource(for: "other"))
        XCTAssertNil(ProviderCatalog.statusPageURL(for: "other"))
    }
}

private final class StubStatusSource: ServiceStatusSource, @unchecked Sendable {
    private(set) var calls = 0
    private let status: ServiceStatus

    init(status: ServiceStatus) {
        self.status = status
    }

    func fetchStatus() async throws -> ServiceStatus {
        calls += 1
        return status
    }
}
