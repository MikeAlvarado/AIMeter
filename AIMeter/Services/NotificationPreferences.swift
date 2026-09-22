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
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard

    init(accountID: String) {
        self.accountID = accountID
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
    case earlyReset
    case reauth

    var title: String {
        switch self {
        case .nearLimit: String(localized: "Near-limit warnings")
        case .limitReached: String(localized: "Limit reached")
        case .runOut: String(localized: "Run-out warnings")
        case .earlyReset: String(localized: "Early-reset alerts")
        case .reauth: String(localized: "Sign-in alerts")
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
        case .earlyReset: earlyResetAlertsEnabled
        case .reauth: reauthAlertsEnabled
        }
    }

    func setEnabled(_ enabled: Bool, _ alert: SmartAlert) {
        switch alert {
        case .nearLimit: nearLimitEnabled = enabled
        case .limitReached: limitReachedEnabled = enabled
        case .runOut: runOutWarningsEnabled = enabled
        case .earlyReset: earlyResetAlertsEnabled = enabled
        case .reauth: reauthAlertsEnabled = enabled
        }
    }
}
