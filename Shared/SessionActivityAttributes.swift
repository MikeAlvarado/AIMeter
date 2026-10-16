#if os(iOS)
import ActivityKit
import Foundation
import UsageKit

/// Data behind the Session-window Live Activity — lives in `Shared/` since
/// both the app (starts/updates/ends it) and the widget extension (renders
/// it) need the type. iOS only: ActivityKit doesn't exist on macOS.
///
/// `nonisolated`: both targets default to `MainActor` isolation
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION`), which would make this conformance
/// main-actor-isolated — and `Activity.update`/`end` run on the concurrent
/// executor, where an isolated conformance can't be used. It's plain data,
/// so there's nothing to isolate.
nonisolated struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var usedPct: Double
        var resetsAt: Date
        var isPeak: Bool
        /// Carried alongside `usedPct` so `UsageWindow.tint(usedPct:severity:usageColors:)`
        /// can make the same terracotta/yellow/red call every other surface
        /// makes — a provider-flagged "critical"/"exceeded" window should
        /// turn red here too, not just past the raw percentage threshold.
        var severity: UsageWindow.Severity?
    }

    let accountID: String
    let accountName: String
    /// The account's chosen glyph; fixed for the activity's lifetime like
    /// the name, so an icon change restarts it the same way a rename does.
    var accountIcon: AccountIcon? = nil
    /// The account's pet while its "Show a pet" switch is on
    /// (`LiveActivityPreferences.showsPet`), else nil. Fixed like the name,
    /// so turning the switch restarts the activity; one an older build
    /// started decodes with none.
    var pet: Pet? = nil

    /// A pet by its three parts' raw values, which only ever grow at the
    /// end, rather than its `SessionPet.index`, which means another pet
    /// once a creature is added (and an activity can outlive an update).
    nonisolated struct Pet: Codable, Hashable, Sendable {
        var creature: Int
        var palette: Int
        var accessory: Int
    }

    /// Main actor, like `SessionPet` itself (the target's default
    /// isolation): only the views read it.
    @MainActor var sessionPet: SessionPet? {
        guard let pet,
              let creature = SessionPet.Creature(rawValue: pet.creature),
              let palette = SessionPet.Palette(rawValue: pet.palette),
              let accessory = SessionPet.Accessory(rawValue: pet.accessory)
        else { return nil }
        return SessionPet(creature: creature, palette: palette, accessory: accessory)
    }
}
#endif
