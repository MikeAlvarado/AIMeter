#if os(macOS)
import AppKit
import Foundation
import Observation
import UsageKit
import UserNotifications

/// The Mac app keeping itself current (see "Updates" in the repo-root
/// CLAUDE.md): a check a minute after launch and then once a day, while
/// "Check for updates automatically" is on; a newer release is downloaded
/// and verified in the background (`UpdateInstaller.prepare`), and then
/// the user is told: a notification, and an "is ready" notice in the menu
/// bar popover, the Dashboard, the notch island and Settings. Nothing
/// installs until the user picks "Restart to Update" in the notice's
/// window (`UpdateWindow`), which shows the new version's notes. "Later"
/// closes it; the notices stay, and the notification comes back the next
/// day. The same window shows this version's notes once after a version
/// installed by hand.
@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(AppVersion)
        case ready(Prepared)
        case installing
        case failed(String)
    }

    struct Prepared: Equatable {
        let version: AppVersion
        let app: URL
        let notes: WhatsNew.Release?
        let page: URL
    }

    private(set) var phase: Phase = .idle
    private(set) var lastChecked: Date?
    /// This version's notes, after a version installed by hand.
    var notesToShow: WhatsNew.Release?

    var readyUpdate: Prepared? {
        if case .ready(let prepared) = phase { prepared } else { nil }
    }

    /// Whether this copy can update itself at all: a signed build (an
    /// unsigned one has no team to hold the download to).
    @ObservationIgnored let isAvailable = UpdateInstaller.runningTeam != nil

    @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?
    @ObservationIgnored private var firstCheck: Task<Void, Never>?
    private static let remindAfterKey = "pref.updateRemindAfter"
    private static let notifiedKey = "pref.updateNotifiedVersion"
    static let activityID = "com.mikealvarado.aimeter.updates.activity"
    static let checkInterval: TimeInterval = 24 * 3600
    static let firstCheckDelay: Duration = .seconds(60)

    private var defaults: UserDefaults { Preferences.groupDefaults }

    /// `DEBUG` only: `-AIMeterUpdateFeed <url>` points the check at another
    /// feed (a `file://` JSON shaped like GitHub's) to try the whole path
    /// without publishing a release.
    private var feed: URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "AIMeterUpdateFeed"), let url = URL(string: override) {
            return url
        }
        #endif
        return UpdateFeed.latestURL
    }

    // MARK: Lifecycle

    /// At launch: tidy what an earlier update left, show this version's
    /// notes if it was installed by hand, and start the daily check.
    func start(automatic: Bool) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        UpdateInstaller.cleanUp(keeping: nil)
        if let due = WhatsNew.dueAtLaunch() {
            notesToShow = due
            AppChrome.openUpdateWindow()
        }
        setAutomaticChecks(automatic)
    }

    /// Settings' "Check for updates automatically".
    func setAutomaticChecks(_ on: Bool) {
        scheduler?.invalidate()
        scheduler = nil
        firstCheck?.cancel()
        guard on, isAvailable else { return }
        firstCheck = Task { [weak self] in
            try? await Task.sleep(for: Self.firstCheckDelay)
            guard !Task.isCancelled else { return }
            await self?.check(userInitiated: false)
        }
        let scheduler = NSBackgroundActivityScheduler(identifier: Self.activityID)
        scheduler.repeats = true
        scheduler.interval = Self.checkInterval
        scheduler.tolerance = 2 * 3600
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            Task { @MainActor in
                await AppUpdater.shared.check(userInitiated: false)
                completion(.finished)
            }
        }
        self.scheduler = scheduler
    }

    // MARK: Check

    /// Asks the feed, downloads and verifies anything newer, and tells
    /// the user once it is ready. A failure only shows when the user asked.
    func check(userInitiated: Bool) async {
        guard isAvailable, phase != .checking, phase != .installing else { return }
        if case .downloading = phase { return }
        guard let current = AppVersion.current else { return }
        let ready = readyUpdate
        // A ready update keeps its notices up while the next check runs.
        if ready == nil { phase = .checking }
        do {
            let release = try await UpdateFeed.fetchLatest(from: feed)
            lastChecked = Date()
            guard let offer = UpdateFeed.offer(in: release, current: current) else {
                phase = ready.map(Phase.ready) ?? .upToDate
                return
            }
            if let ready, ready.version >= offer.version {
                phase = .ready(ready)
                notifyIfDue(ready)
                return
            }
            phase = .downloading(offer.version)
            let app = try await UpdateInstaller.prepare(offer)
            let notes = Bundle(url: app).flatMap { WhatsNew.load(from: $0) }?.release(offer.version)
            let prepared = Prepared(version: offer.version, app: app, notes: notes, page: offer.page)
            UpdateInstaller.cleanUp(keeping: app)
            phase = .ready(prepared)
            notifyIfDue(prepared)
        } catch {
            if let ready {
                phase = .ready(ready)
            } else {
                phase = userInitiated ? .failed(error.localizedDescription) : .idle
            }
        }
    }

    // MARK: Install

    /// "Restart to Update": quits, swaps, relaunches. Where the running
    /// copy can't be replaced, opens the release page instead.
    func install() {
        guard let ready = readyUpdate else { return }
        guard UpdateInstaller.canReplace(Bundle.main.bundleURL) else {
            NSWorkspace.shared.open(ready.page)
            return
        }
        // The notes were just read in the notice: not again after the restart.
        WhatsNew.lastSeen = ready.version
        phase = .installing
        do {
            try UpdateInstaller.installAndRelaunch(update: ready.app)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// "Later": the notices stay; the notification returns tomorrow.
    func later() {
        defaults.set(Date().addingTimeInterval(Self.checkInterval), forKey: Self.remindAfterKey)
    }

    /// The window's "Continue" after this version's notes.
    func dismissNotes() {
        notesToShow = nil
        WhatsNew.lastSeen = AppVersion.current
    }

    // MARK: Notification

    /// One notification per version, and again a day after "Later".
    private func notifyIfDue(_ prepared: Prepared) {
        let version = prepared.version.description
        let remindAfter = defaults.object(forKey: Self.remindAfterKey) as? Date
        let alreadyTold = defaults.string(forKey: Self.notifiedKey) == version
        guard !alreadyTold || (remindAfter.map { $0 <= Date() } ?? false) else { return }
        defaults.set(version, forKey: Self.notifiedKey)
        defaults.removeObject(forKey: Self.remindAfterKey)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "AIMeter \(version) is ready")
        content.body = String(localized: "See what's new and restart to update.")
        let request = UNNotificationRequest(identifier: Self.notificationPrefix + version, content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    nonisolated static let notificationPrefix = "update."
}
#endif
