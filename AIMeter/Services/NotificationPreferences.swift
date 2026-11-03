import Foundation
import UsageKit

/// Notification toggles, stored in the App Group so future surfaces (e.g.
/// widget configuration) can read them too. All off by default except
/// `reauthAlertsEnabled` — see the reasoning on that property. Per-window
/// "reset" toggles are the free baseline; the "smart" toggles (run-out
/// warnings, early-reset alerts, near-limit, limit-reached) are global
/// across windows but scoped to one `accountID` — each connected account
/// has its own independent set, so muting a secondary account never
/// touches another's. `peakEnabled` is the deliberate exception: it's one
/// Claude-wide policy, not tied to any specific account, so its key stays
/// unscoped regardless of which account's `NotificationPreferences` reads it.
struct NotificationPreferences {
    let accountID: String
    private let defaults: UserDefaults

    /// `defaults` is the App Group suite in the app; tests hand in a
    /// throwaway suite.
    init(accountID: String, defaults: UserDefaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard) {
        self.accountID = accountID
        self.defaults = defaults
    }

    func isEnabled(for kind: UsageWindow.Kind) -> Bool {
        defaults.bool(forKey: key(for: kind))
    }

    func setEnabled(_ enabled: Bool, for kind: UsageWindow.Kind) {
        defaults.set(enabled, forKey: key(for: kind))
    }

    /// "At this rate, [window] runs out before it resets" warnings.
    var runOutWarningsEnabled: Bool {
        get { defaults.bool(forKey: scopedKey("notify.runout")) }
        nonmutating set { defaults.set(newValue, forKey: scopedKey("notify.runout")) }
    }

    /// "[window] refilled early" alerts.
    var earlyResetAlertsEnabled: Bool {
        get { defaults.bool(forKey: scopedKey("notify.earlyReset")) }
        nonmutating set { defaults.set(newValue, forKey: scopedKey("notify.earlyReset")) }
    }

    /// "[window] nearing its limit" warnings, fired when used% crosses
    /// `nearLimitThreshold` upward.
    var nearLimitEnabled: Bool {
        get { defaults.bool(forKey: scopedKey("notify.nearLimit")) }
        nonmutating set { defaults.set(newValue, forKey: scopedKey("notify.nearLimit")) }
    }

    /// User-set used% at which the near-limit warning fires. Default 80,
    /// kept below the limit-reached threshold so the two don't collide.
    var nearLimitThreshold: Double {
        get {
            let stored = defaults.double(forKey: scopedKey("notify.nearLimitThreshold"))
            return stored == 0 ? 80 : stored
        }
        nonmutating set {
            defaults.set(min(95, max(50, newValue)), forKey: scopedKey("notify.nearLimitThreshold"))
        }
    }

    /// Up to three levels the near-limit warning fires at, in the order
    /// the user set them (the card's rows). An account set before there
    /// were several has its one `nearLimitThreshold`; the first level is
    /// written back there too.
    var nearLimitThresholds: [Double] {
        get {
            if let stored = defaults.array(forKey: scopedKey("notify.nearLimitThresholds")) as? [Double], !stored.isEmpty {
                return Array(stored.prefix(Self.maxNearLimitThresholds))
            }
            return [nearLimitThreshold]
        }
        nonmutating set {
            let levels = Array(newValue.prefix(Self.maxNearLimitThresholds).map { min(95, max(50, $0)) })
            guard let first = levels.first else { return }
            defaults.set(levels, forKey: scopedKey("notify.nearLimitThresholds"))
            nearLimitThreshold = first
        }
    }

    static let maxNearLimitThresholds = 3

    /// "[window] ahead of pace": a window pulling 15 points or more ahead
    /// of a steady burn to its reset (`PaceDetector`), once per window.
    var aheadOfPaceEnabled: Bool {
        get { defaults.bool(forKey: scopedKey("notify.aheadOfPace")) }
        nonmutating set { defaults.set(newValue, forKey: scopedKey("notify.aheadOfPace")) }
    }

    /// The reset of the window an ahead-of-pace warning last went out for,
    /// per kind: one warning per window, however it moves around the line.
    func aheadOfPaceWarned(for kind: UsageWindow.Kind) -> Date? {
        defaults.object(forKey: scopedKey("notify.aheadWarned.\(kind.storageKey)")) as? Date
    }

    func setAheadOfPaceWarned(_ reset: Date, for kind: UsageWindow.Kind) {
        defaults.set(reset, forKey: scopedKey("notify.aheadWarned.\(kind.storageKey)"))
    }

    /// "[window] limit reached" alerts (message adapts to whether the
    /// account has credits).
    var limitReachedEnabled: Bool {
        get { defaults.bool(forKey: scopedKey("notify.limitReached")) }
        nonmutating set { defaults.set(newValue, forKey: scopedKey("notify.limitReached")) }
    }

    /// "Sign in again" alerts, fired when this account's stored login
    /// stops working (`UsageError.notAuthenticated`).
    ///
    /// The one family that defaults to **on**, deliberately breaking the
    /// "every toggle off by default" rule the other five follow: those
    /// announce *usage*, which the user can always go look at, whereas this
    /// one announces that AIMeter has stopped being able to look at all.
    /// Silence there is indistinguishable from "nothing has changed", so an
    /// opt-in default would mean the app quietly shows stale numbers for
    /// days — the exact failure this alert exists to prevent. It is also
    /// self-limiting: it fires once per breakage (see
    /// `reauthAlertDelivered`), not on a schedule. Being on by default
    /// still never means a surprise prompt — like every family here it only
    /// delivers if notification permission was already granted.
    var reauthAlertsEnabled: Bool {
        get { bool(scopedKey("notify.reauth"), default: true) }
        nonmutating set { defaults.set(newValue, forKey: scopedKey("notify.reauth")) }
    }

    /// Whether the *current* broken sign-in has already been announced.
    /// Set when the alert is delivered and cleared by the next successful
    /// refresh (or a reconnect), so a login that breaks, gets fixed, and
    /// breaks again alerts twice — while a login that stays broken across
    /// every refresh for days alerts once.
    var reauthAlertDelivered: Bool {
        get { defaults.bool(forKey: scopedKey("notify.reauth.delivered")) }
        nonmutating set { defaults.set(newValue, forKey: scopedKey("notify.reauth.delivered")) }
    }

    /// "Peak hours started/ended" alerts, scheduled from Claude's fixed
    /// weekday schedule rather than anything fetched. Deliberately global —
    /// see the type doc above.
    var peakEnabled: Bool {
        get { defaults.bool(forKey: "notify.peak") }
        nonmutating set { defaults.set(newValue, forKey: "notify.peak") }
    }

    /// "Notify about incidents": a notification when a connected service's
    /// status page reports one. Global like `peakEnabled`: an incident is
    /// the service's, not an account's. Off by default.
    var incidentAlertsEnabled: Bool {
        get { defaults.bool(forKey: "notify.incidents") }
        nonmutating set { defaults.set(newValue, forKey: "notify.incidents") }
    }

    /// The incident already announced for a provider family (its title, or
    /// the page's summary), so the next check of the same one stays quiet.
    func announcedIncident(for providerID: String) -> String? {
        defaults.string(forKey: "notify.incident.announced.\(providerID)")
    }

    func setAnnouncedIncident(_ incident: String?, for providerID: String) {
        defaults.set(incident, forKey: "notify.incident.announced.\(providerID)")
    }

    /// `UserDefaults.bool(forKey:)` reports `false` for a key nobody has
    /// written, which would silently flip any preference whose default is
    /// `true` — same trap, and same presence check, as
    /// `Preferences.bool(_:_:default:)`.
    private func bool(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    /// Removes every key scoped to this account — called on disconnect,
    /// the one time an accountID stops existing. Enumerates by suffix
    /// rather than listing the properties above, so a toggle added later
    /// can't be forgotten here; the unscoped global keys have no suffix
    /// and are untouched.
    func clear() {
        let suffix = ".\(accountID)"
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("notify.") && key.hasSuffix(suffix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(for kind: UsageWindow.Kind) -> String {
        scopedKey("notify.\(kind.storageKey)")
    }

    private func scopedKey(_ base: String) -> String {
        "\(base).\(accountID)"
    }
}

/// The per-account "smart" alert families — one toggle each, all off by
/// default except `reauth` (see `NotificationPreferences.reauthAlertsEnabled`).
/// The order is the order the toggles card lists them in.
enum SmartAlert: CaseIterable {
    case nearLimit
    case limitReached
    case runOut
    case aheadOfPace
    case earlyReset
    case reauth

    var title: String {
        switch self {
        case .nearLimit: String(localized: "Near-limit warnings")
        case .limitReached: String(localized: "Limit reached")
        case .runOut: String(localized: "Run-out warnings")
        case .aheadOfPace: String(localized: "Ahead-of-pace warnings")
        case .earlyReset: String(localized: "Early-reset alerts")
        case .reauth: String(localized: "Sign-in alerts")
        }
    }

    /// One line under the toggle: what fires it. Until 4.3.1 the five
    /// were explained in one paragraph under the card.
    var detail: String {
        switch self {
        case .nearLimit: String(localized: "When a limit passes one of the levels you set.")
        case .limitReached: String(localized: "When a limit runs out, and whether credits take over.")
        case .runOut: String(localized: "Ahead of time, when your pace would use a limit up early.")
        case .aheadOfPace: String(localized: "Once per window, when a limit runs 15 points ahead of a steady pace to its reset.")
        case .earlyReset: String(localized: "When a limit refills before its scheduled reset.")
        case .reauth: String(localized: "When the service stops accepting this account's sign-in. On by default, since nothing else would tell you the figures stopped updating.")
        }
    }
}

extension NotificationPreferences {
    /// The named properties above, addressed by family — what lets
    /// `UsageModel` and the toggles card treat the five identically
    /// instead of repeating one getter/setter pair per family.
    func isEnabled(_ alert: SmartAlert) -> Bool {
        switch alert {
        case .nearLimit: nearLimitEnabled
        case .limitReached: limitReachedEnabled
        case .runOut: runOutWarningsEnabled
        case .aheadOfPace: aheadOfPaceEnabled
        case .earlyReset: earlyResetAlertsEnabled
        case .reauth: reauthAlertsEnabled
        }
    }

    func setEnabled(_ enabled: Bool, _ alert: SmartAlert) {
        switch alert {
        case .nearLimit: nearLimitEnabled = enabled
        case .limitReached: limitReachedEnabled = enabled
        case .runOut: runOutWarningsEnabled = enabled
        case .aheadOfPace: aheadOfPaceEnabled = enabled
        case .earlyReset: earlyResetAlertsEnabled = enabled
        case .reauth: reauthAlertsEnabled = enabled
        }
    }
}
