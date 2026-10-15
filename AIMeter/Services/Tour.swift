import Foundation
import UsageKit

/// One part of AIMeter the tour can explain and, where it can be switched
/// on, switch on (see "Tour" in `AIMeter/CLAUDE.md`). The raw value is
/// what a release's notes name in `WhatsNew.json` (`feature`), so a new
/// feature's note can carry the same card and button the tour shows.
enum TourFeature: String, CaseIterable, Codable, Sendable {
    case welcome, widgets, alerts, colors, notchIsland, sessions, sessionNames, openAtLogin, connect
}

/// The guided tour: on a fresh install, every step in `steps`, one at a
/// time, each with an animation of what it is and a button that turns it
/// on; after an update, a card for each new feature the notes name. What
/// was offered is remembered, so an update never offers it twice.
enum Tour {
    /// The full tour's steps on this platform, in order: what AIMeter is,
    /// the parts worth turning on, and connecting last. A step whose
    /// feature can't show here is passed over as the tour runs
    /// (`TourActions.applies`): Claude Code's sessions without the notch
    /// island, or on a Mac where Claude Code has never run.
    static var steps: [TourFeature] {
        #if os(macOS)
        [.welcome, .notchIsland, .sessions, .sessionNames, .alerts, .openAtLogin, .connect]
        #else
        [.welcome, .widgets, .alerts, .connect]
        #endif
    }

    /// The full tour runs once: on an install that has never finished or
    /// skipped it and has no account yet (an install from before the tour
    /// had one, and gets the new features' cards instead).
    static func isDue(completed: Bool, hasPriorInstall: Bool) -> Bool {
        !completed && !hasPriorInstall
    }

    /// The features `release` names that this install hasn't been offered
    /// yet and that still have something to turn on (`canOffer`: the
    /// feature applies here and is off): the cards to show after an update
    /// whose notes were already read, on the Mac in the notice before the
    /// restart, where the new version couldn't act yet.
    static func pendingOffers(in release: WhatsNew.Release?, offered: Set<TourFeature>, canOffer: (TourFeature) -> Bool) -> WhatsNew.Release? {
        guard let release else { return nil }
        let items = release.items.filter { item in
            guard let feature = item.tourFeature else { return false }
            return !offered.contains(feature) && feature.canBeTurnedOn && canOffer(feature)
        }
        return items.isEmpty ? nil : WhatsNew.Release(version: release.version, items: items)
    }

    // MARK: Stored

    static let completedKey = "pref.tourCompleted"
    static let offeredKey = "pref.tourOfferedFeatures"

    @MainActor
    static var completed: Bool {
        get { Preferences.groupDefaults.bool(forKey: completedKey) }
        set { Preferences.groupDefaults.set(newValue, forKey: completedKey) }
    }

    @MainActor
    static var offered: Set<TourFeature> {
        get { Set((Preferences.groupDefaults.stringArray(forKey: offeredKey) ?? []).compactMap(TourFeature.init)) }
        set { Preferences.groupDefaults.set(newValue.map(\.rawValue).sorted(), forKey: offeredKey) }
    }

    @MainActor
    static func markOffered(_ features: some Sequence<TourFeature>) {
        offered.formUnion(features)
    }

    /// Whether the full tour should open at this launch. Read before
    /// `WhatsNew.dueAtLaunch`, and never under the unit-test host.
    /// `DEBUG` only: `-AIMeterShowTour YES` opens it on any install, to
    /// check or capture it without resetting one.
    @MainActor
    static func dueAtLaunch() -> Bool {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return false }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "AIMeterShowTour") { return true }
        #endif
        let prior = !(AccountRegistryStore(suiteName: AppConfig.appGroupID)?.accounts().isEmpty ?? true)
        return isDue(completed: completed, hasPriorInstall: prior)
    }

    /// The tour was finished or skipped: it doesn't open again on its own
    /// (Settings can open it), its features count as offered, and this
    /// version's notes as read, since the tour already showed what is new.
    @MainActor
    static func finish() {
        completed = true
        markOffered(steps)
        if let current = AppVersion.current, (WhatsNew.lastSeen ?? AppVersion("0")!) < current {
            WhatsNew.lastSeen = current
        }
    }

    #if os(macOS)
    /// Whether Claude Code has run on this Mac (its logs folder exists),
    /// the same test as the Dashboard's invitation to its usage.
    static var claudeCodePresent: Bool {
        FileManager.default.fileExists(atPath: ClaudeSessionLogWatcher.defaultRoot.path)
    }
    #else
    /// "Show the tour" in the iOS Settings sheet: the tour opens once the
    /// sheet is gone (`deliverPendingShow`, from the sheet's `onDismiss`),
    /// since nothing can be presented over a sheet that is going away.
    @MainActor static var showRequested = false

    @MainActor
    static func deliverPendingShow() {
        guard showRequested else { return }
        showRequested = false
        NotificationCenter.default.post(name: .tourShowRequest, object: nil)
    }
    #endif
}

extension TourFeature {
    /// Features with a switch, a permission or a sign-in behind them;
    /// the rest only explain (the welcome, where widgets live, the colors,
    /// which are on already).
    var canBeTurnedOn: Bool {
        switch self {
        case .welcome, .widgets, .colors: false
        case .alerts, .notchIsland, .sessions, .sessionNames, .openAtLogin, .connect: true
        }
    }
}

extension WhatsNew.Item {
    /// The tour feature this note shows a card for, if it names one.
    var tourFeature: TourFeature? { feature.flatMap(TourFeature.init) }
}
