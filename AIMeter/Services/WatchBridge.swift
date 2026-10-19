#if os(iOS)
import Foundation
import UsageKit
import WatchConnectivity

/// The iPhone's side of the Watch app: sends it what to show, and answers
/// its refresh requests. The Watch holds no credentials and never fetches
/// (see "Apple Watch" in the repo-root CLAUDE.md); its freshness is the
/// phone's, so every sweep and every change to the accounts or the
/// display preferences ends here, coalesced into one send
/// (`updateApplicationContext`, which keeps only the latest). A
/// snapshot that changed also goes through the complication transfer,
/// budgeted by watchOS to about fifty a day, so one per sweep at most.
final class WatchBridge: NSObject {
    /// nil on an iPad or where there is no Watch to pair.
    static func makeIfSupported() -> WatchBridge? {
        WCSession.isSupported() ? WatchBridge() : nil
    }

    weak var model: UsageModel?
    /// `DEBUG` only: with `-AIMeterDemo YES` the demo's accounts reach
    /// the Watch too, so a simulator pair and the store's Watch captures
    /// have figures to show. A real demo sends nothing.
    static var demoReachesWatch: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "AIMeterDemo")
        #else
        false
        #endif
    }
    private let session = WCSession.default
    private var lastSent: WatchPayload?
    private var pending: Task<Void, Never>?

    private override init() {
        super.init()
        session.delegate = self
        session.activate()
    }

    /// Sends soon: a sweep lands its accounts one by one, and a burst of
    /// Settings changes writes several keys, each worth one send.
    func pushSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            push()
        }
    }

    func push() {
        guard let model, !model.isDemoMode || Self.demoReachesWatch,
              session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let payload = try? model.watchPayload, payload != lastSent,
              let context = try? payload.contextDictionary() else { return }
        try? session.updateApplicationContext(context)
        // Only a changed figure is worth a complication's own transfer:
        // the application context reaches the app, not a face.
        if session.isComplicationEnabled,
           session.remainingComplicationUserInfoTransfers > 0,
           payload.accounts.map(\.snapshot) != lastSent?.accounts.map(\.snapshot) {
            session.transferCurrentComplicationUserInfo(context)
        }
        lastSent = payload
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // A new Watch was paired: the session is to be activated again.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    /// The Watch asks for fresh figures (its Refresh button, or its own
    /// background refresh); this wakes the app in the background if it
    /// isn't running. The reply carries the payload, whatever the fetch did.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let wantsRefresh = message[WatchPayload.refreshKey] != nil
        let reply = ReplyHandler(replyHandler)
        Task { @MainActor in
            if wantsRefresh {
                await self.model?.refreshAllIfStale()
            }
            let context = (try? self.model?.watchPayload.contextDictionary()) ?? [:]
            reply.send(context)
            self.push()
        }
    }
}

/// The reply closure, carried across the hop to the main actor.
private nonisolated struct ReplyHandler: @unchecked Sendable {
    private let handler: ([String: Any]) -> Void

    init(_ handler: @escaping ([String: Any]) -> Void) {
        self.handler = handler
    }

    func send(_ reply: [String: Any]) {
        handler(reply)
    }
}

extension UsageModel {
    /// What the Watch shows: every connected account in the Dashboard's
    /// order with its last snapshot, and the preferences it draws with.
    var watchPayload: WatchPayload {
        get throws {
            WatchPayload(
                accounts: accounts.map { usage in
                    WatchPayload.Account(
                        accountID: usage.account.accountID, providerID: usage.account.providerID,
                        displayName: usage.account.displayName, icon: usage.account.icon, snapshot: usage.snapshot
                    )
                },
                prefs: WatchPayload.Prefs(Preferences.load())
            )
        }
    }
}
#endif
