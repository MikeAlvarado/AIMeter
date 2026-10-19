import XCTest
import UsageKit
@testable import AIMeter

/// iCloud sync over a dictionary in place of the key-value store: what a
/// device sends, what another takes, that nothing echoes, and what
/// leaves the store. Nothing here touches iCloud or the App Group.
@MainActor
final class CloudSyncTests: XCTestCase {
    final class FakeStore: CloudKeyValueStore {
        var values: [String: Data] = [:]
        var writes = 0
        func data(forKey key: String) -> Data? { values[key] }
        func set(_ data: Data?, forKey key: String) { writes += 1; values[key] = data }
        var allKeys: [String] { Array(values.keys) }
        func synchronize() -> Bool { true }
    }

    /// One device: its own defaults, timeline folder and registry.
    struct Device {
        let scratch: ScratchDefaults
        let directory: URL
        let registry: AccountRegistryStore
        let timelines: UsageTimelineStore
        let sync: CloudSync

        init(store: FakeStore, accountID: String, identity: String?) {
            scratch = ScratchDefaults()
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-\(UUID().uuidString)")
            registry = AccountRegistryStore(userDefaults: scratch.defaults)
            var account = ConnectedAccount.managed(accountID, name: "Work")
            account.syncIdentity = identity
            registry.add(account)
            timelines = UsageTimelineStore(directory: directory)
            sync = CloudSync(store: store, timelines: timelines, registry: registry, defaults: scratch.defaults)
        }

        var account: ConnectedAccount { registry.accounts()[0] }

        func wipe() {
            sync.stop()
            scratch.wipe()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private var devices: [Device] = []
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    override func tearDown() {
        for device in devices { device.wipe() }
        devices = []
        super.tearDown()
    }

    private func device(_ store: FakeStore, accountID: String, identity: String?) -> Device {
        let device = Device(store: store, accountID: accountID, identity: identity)
        devices.append(device)
        return device
    }

    private func sample(_ used: Double, at date: Date) -> TimelineSample {
        TimelineSample(timestamp: date, usedPct: used, resetsAt: nil)
    }

    // MARK: History

    func testAnAccountsHistoryReachesTheOtherDeviceAndMerges() {
        let store = FakeStore()
        let phone = device(store, accountID: "phone-1", identity: "claude:acct-1")
        phone.timelines.record(.make(windows: [.make(.session, used: 40)]), for: "phone-1", at: now)
        phone.sync.pushHistory(for: phone.account, now: now)
        XCTAssertEqual(store.allKeys, [CloudSync.key(for: "claude:acct-1")])
        XCTAssertFalse(store.allKeys[0].contains("acct-1"), "the key is a digest, never the id")

        // The Mac: the same login under another accountID, with a sample
        // of its own half an hour later.
        let mac = device(store, accountID: "mac-7", identity: "claude:acct-1")
        mac.timelines.record(.make(windows: [.make(.session, used: 55)]), for: "mac-7", at: now.addingTimeInterval(1800))
        var landed: [String] = []
        mac.sync.onRemoteHistory = { landed.append($0) }
        mac.sync.start(preferences: Preferences(), now: now)
        XCTAssertEqual(landed, ["mac-7"])
        XCTAssertEqual(mac.timelines.samples(for: "mac-7", kind: .session).map(\.usedPct), [40, 55])

        // The Mac's union goes back out, and the phone takes the Mac's sample.
        mac.sync.pushHistory(for: mac.account, now: now)
        var phoneLanded: [String] = []
        phone.sync.onRemoteHistory = { phoneLanded.append($0) }
        phone.sync.pull(keys: store.allKeys)
        XCTAssertEqual(phoneLanded, ["phone-1"])
        XCTAssertEqual(phone.timelines.samples(for: "phone-1", kind: .session).map(\.usedPct), [40, 55])
        // Both hold the same series now: pulling again changes nothing.
        phone.sync.pull(keys: store.allKeys)
        XCTAssertEqual(phoneLanded, ["phone-1"])
    }

    func testAnUnchangedSeriesIsNotSentAgain() {
        let store = FakeStore()
        let phone = device(store, accountID: "phone-1", identity: "claude:acct-1")
        phone.timelines.record(.make(windows: [.make(.session, used: 40)]), for: "phone-1", at: now)
        phone.sync.pushHistory(for: phone.account, now: now)
        let writes = store.writes
        phone.sync.pushHistory(for: phone.account, now: now)
        XCTAssertEqual(store.writes, writes)
        phone.timelines.record(.make(windows: [.make(.session, used: 48)]), for: "phone-1", at: now.addingTimeInterval(1800))
        phone.sync.pushHistory(for: phone.account, now: now)
        XCTAssertEqual(store.writes, writes + 1)
    }

    func testAnotherLoginsHistoryAndAMisfiledKeyAreIgnored() throws {
        let store = FakeStore()
        let other = CloudSync.HistoryEnvelope(identity: "claude:acct-2", updatedAt: now, windows: ["session": [sample(80, at: now)]])
        store.set(try CloudSync.encode(other), forKey: CloudSync.key(for: "claude:acct-2"))
        let misfiled = CloudSync.HistoryEnvelope(identity: "claude:acct-1", updatedAt: now, windows: ["session": [sample(80, at: now)]])
        store.set(try CloudSync.encode(misfiled), forKey: CloudSync.historyPrefix + "somewhere-else")
        store.set(Data("not an envelope".utf8), forKey: CloudSync.key(for: "claude:acct-1"))

        let mac = device(store, accountID: "mac-7", identity: "claude:acct-1")
        var landed: [String] = []
        mac.sync.onRemoteHistory = { landed.append($0) }
        mac.sync.start(preferences: Preferences(), now: now)
        XCTAssertTrue(landed.isEmpty)
        XCTAssertTrue(mac.timelines.samples(for: "mac-7", kind: .session).isEmpty)
    }

    func testAnAccountWithoutAnIdentityStaysOnItsDevice() {
        let store = FakeStore()
        let phone = device(store, accountID: "phone-1", identity: nil)
        phone.timelines.record(.make(windows: [.make(.session, used: 40)]), for: "phone-1", at: now)
        phone.sync.pushHistory(for: phone.account, now: now)
        XCTAssertTrue(store.allKeys.isEmpty)
    }

    // MARK: Preferences

    func testPreferencesFollowTheNewestChangeAndNeverEcho() {
        let store = FakeStore()
        let phone = device(store, accountID: "phone-1", identity: nil)
        var phonePrefs = Preferences()
        phonePrefs.displayMode = .remaining
        phone.sync.pushPreferences(phonePrefs, now: now)
        let writes = store.writes
        phone.sync.pushPreferences(phonePrefs, now: now.addingTimeInterval(1))
        XCTAssertEqual(store.writes, writes, "the same choices are not sent again")

        // The Mac starts with the defaults and nothing of its own recorded:
        // it takes the phone's and sends nothing back.
        let mac = device(store, accountID: "mac-7", identity: nil)
        var applied: [CloudSync.SyncedPreferences] = []
        mac.sync.onRemotePreferences = { applied.append($0) }
        mac.sync.start(preferences: Preferences(), now: now.addingTimeInterval(2))
        XCTAssertEqual(applied.map(\.displayMode), [DisplayMode.remaining.rawValue])
        XCTAssertEqual(store.writes, writes)
        // Applying them writes the app's preferences, which come back here
        // as a change: the same choices, so still nothing is sent.
        mac.sync.pushPreferences(phonePrefs, now: now.addingTimeInterval(3))
        XCTAssertEqual(store.writes, writes)

        // The Mac changes a choice: the phone takes it, once.
        var macPrefs = phonePrefs
        macPrefs.usageColors = false
        mac.sync.pushPreferences(macPrefs, now: now.addingTimeInterval(60))
        var phoneApplied: [CloudSync.SyncedPreferences] = []
        phone.sync.onRemotePreferences = { phoneApplied.append($0) }
        phone.sync.pull(keys: [CloudSync.prefsKey])
        phone.sync.pull(keys: [CloudSync.prefsKey])
        XCTAssertEqual(phoneApplied.map(\.usageColors), [false])
    }

    func testADevicesOwnNewerChangeIsNotOverwrittenAtLaunch() {
        let store = FakeStore()
        let phone = device(store, accountID: "phone-1", identity: nil)
        phone.sync.pushPreferences(Preferences(), now: now)

        // The Mac changed its own preferences later, offline (its stamp is
        // newer than the store's): at launch it keeps them and sends them.
        let mac = device(store, accountID: "mac-7", identity: nil)
        mac.scratch.defaults.set(now.addingTimeInterval(60), forKey: CloudSync.prefsStampKey)
        var macPrefs = Preferences()
        macPrefs.resetStyle = .absolute
        var applied: [CloudSync.SyncedPreferences] = []
        mac.sync.onRemotePreferences = { applied.append($0) }
        mac.sync.start(preferences: macPrefs, now: now.addingTimeInterval(120))
        XCTAssertTrue(applied.isEmpty)
        let sent = try? JSONDecoder().decode(CloudSync.SyncedPreferences.self, from: store.data(forKey: CloudSync.prefsKey) ?? Data())
        XCTAssertEqual(sent?.resetStyle, ResetStyle.absolute.rawValue)
    }

    func testAValueThisBuildDoesNotKnowIsLeftAlone() {
        let prefs = PreferencesModel(defaults: ScratchDefaults().defaults)
        prefs.displayMode = .remaining
        var remote = CloudSync.SyncedPreferences(Preferences(), updatedAt: now)
        remote.displayMode = "percentOfSomethingNewer"
        remote.usageColors = false
        remote.apply(to: prefs)
        XCTAssertEqual(prefs.displayMode, .remaining)
        XCTAssertFalse(prefs.usageColors)
    }

    // MARK: Leaving the store

    func testTurningOffRemovesWhatAIMeterKeptAndNothingElse() {
        let store = FakeStore()
        store.set(Data(), forKey: "someone.else")
        let phone = device(store, accountID: "phone-1", identity: "claude:acct-1")
        phone.timelines.record(.make(windows: [.make(.session, used: 40)]), for: "phone-1", at: now)
        phone.sync.pushPreferences(Preferences(), now: now)
        phone.sync.pushHistory(for: phone.account, now: now)
        XCTAssertEqual(store.allKeys.count, 3)
        phone.sync.removeAll()
        XCTAssertEqual(store.allKeys, ["someone.else"])
    }

    func testADisconnectedAccountsHistoryLeavesTheStore() {
        let store = FakeStore()
        let phone = device(store, accountID: "phone-1", identity: "claude:acct-1")
        phone.timelines.record(.make(windows: [.make(.session, used: 40)]), for: "phone-1", at: now)
        phone.sync.pushPreferences(Preferences(), now: now)
        phone.sync.pushHistory(for: phone.account, now: now)
        phone.sync.removeHistory(identity: "claude:acct-1")
        XCTAssertEqual(store.allKeys, [CloudSync.prefsKey])
    }

    // MARK: The model

    func testAFetchedIdentityIsWrittenToTheRegistry() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let registry = AccountRegistryStore(userDefaults: scratch.defaults)
        registry.add(.managed("acc", name: "Work"))
        let model = UsageModel(registry: registry, platformServices: false)
        model.syncToCloud(accountID: "acc", identity: "claude:acct-1")
        XCTAssertEqual(registry.account(for: "acc")?.syncIdentity, "claude:acct-1")
        XCTAssertEqual(model.accounts.first?.account.syncIdentity, "claude:acct-1")
        // A profile without an id keeps the known one.
        model.syncToCloud(accountID: "acc", identity: nil)
        XCTAssertEqual(registry.account(for: "acc")?.syncIdentity, "claude:acct-1")
    }
}
