import Foundation
import Observation
import UsageKit
import WatchConnectivity
import WatchKit
import WidgetKit

/// The Watch's copy of what the iPhone sent (`WatchPayload`): kept in the
/// Watch's own App Group, in the same stores the phone's widgets read
/// (`AccountRegistryStore`, `SnapshotStore`, `Preferences`), so the
/// complications and the app draw with the phone's own code. The iPhone
/// is the only source; the Watch writes only what it was sent.
@Observable
final class WatchStore: NSObject {
    static let shared = WatchStore()

    private(set) var accounts: [ConnectedAccount] = []
    private(set) var snapshots: [String: UsageSnapshot] = [:]
    private(set) var prefs = Preferences.load()
    /// When the iPhone last sent a payload, nil before the first.
    private(set) var receivedAt: Date?
    private(set) var isRequesting = false
    /// The last request got no answer: the iPhone out of reach.
    private(set) var requestFailed = false

    @ObservationIgnored private let registry = AccountRegistryStore(suiteName: AppConfig.appGroupID)
    @ObservationIgnored private let snapshotStore = SnapshotStore(suiteName: AppConfig.appGroupID)
    @ObservationIgnored private let defaults = Preferences.groupDefaults
    @ObservationIgnored private let session = WCSession.default

    private override init() {
        super.init()
        reload()
        session.delegate = self
        session.activate()
    }

    /// Older than `AppConfig.staleAfter`, or never received.
    var isStale: Bool {
        guard let receivedAt else { return true }
        return Date().timeIntervalSince(receivedAt) > AppConfig.staleAfter
    }

    func reload() {
        accounts = registry?.accounts() ?? []
        snapshots = Dictionary(uniqueKeysWithValues: accounts.compactMap { account in
            snapshotStore?.snapshot(for: account.accountID).map { (account.accountID, $0) }
        })
        prefs = Preferences.load()
        receivedAt = defaults.object(forKey: WatchPayload.receivedAtKey) as? Date
    }

    func apply(_ payload: WatchPayload) {
        guard let registry, let snapshotStore else { return }
        payload.apply(registry: registry, snapshots: snapshotStore, defaults: defaults)
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Asks the iPhone for fresh figures. The reply is a payload; no
    /// reply (the iPhone out of reach) leaves what the Watch has.
    func requestRefresh() {
        guard session.activationState == .activated, session.isReachable else {
            requestFailed = true
            return
        }
        isRequesting = true
        session.sendMessage([WatchPayload.refreshKey: true]) { reply in
            let payload = WatchPayload(context: reply)
            Task { @MainActor in
                if let payload { self.apply(payload) }
                self.isRequesting = false
                self.requestFailed = false
            }
        } errorHandler: { _ in
            Task { @MainActor in
                self.isRequesting = false
                self.requestFailed = true
            }
        }
    }

    func requestRefreshIfStale() {
        guard isStale else { return }
        requestRefresh()
    }

    static func scheduleBackgroundRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: AppConfig.widgetRefreshFloor), userInfo: nil
        ) { _ in }
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        // What the iPhone sent before this launch, if anything.
        let payload = WatchPayload(context: session.receivedApplicationContext)
        Task { @MainActor in
            if let payload { self.apply(payload) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let payload = WatchPayload(context: applicationContext)
        Task { @MainActor in
            if let payload { self.apply(payload) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let payload = WatchPayload(context: userInfo)
        Task { @MainActor in
            if let payload { self.apply(payload) }
        }
    }
}
