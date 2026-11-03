import Foundation
import UsageKit

/// Two small readings of figures the app already has, pure so they are
/// tested: how much of a long window fits in today, and which other
/// account of the same service still has room.
enum UsageInsights {
    /// Windows shorter than this have no "today": a session is over in
    /// hours.
    static let dailyAllowanceMinimumDuration: TimeInterval = 6 * 86_400

    /// What is left of a window divided by the days until it resets, today
    /// counting as one: "up to 9 % today" so the week lasts. Nil for a
    /// window shorter than six days, one with no reset ahead, or one with
    /// nothing left.
    static func dailyAllowance(for window: UsageWindow, now: Date = Date()) -> Double? {
        guard let duration = window.effectiveDuration, duration >= dailyAllowanceMinimumDuration,
              let resetsAt = window.resetsAt, resetsAt > now else { return nil }
        let left = 100 - window.usedPct
        guard left > 0 else { return nil }
        let days = max(1, (resetsAt.timeIntervalSince(now) / 86_400).rounded(.up))
        return left / days
    }

    /// From this figure on an account counts as nearly out, the bars'
    /// red (`UsageLevel.dangerAbove`).
    static let nearlyOutAbove: Double = 85
    /// Another account is worth pointing at only below this.
    static let roomBelow: Double = 50

    struct Room: Equatable {
        let accountID: String
        let name: String
        /// 0–100, what its most used window leaves.
        let freePct: Double
    }

    /// The account of the same service with the most room, when `urgency`
    /// (this account's, `AccountOrder.urgency`) is nearly out and another
    /// one is under half used. Only the same service: those are the
    /// accounts the user can switch between.
    static func room(
        forUrgency urgency: Double?,
        providerID: String,
        accountID: String,
        among others: [(account: ConnectedAccount, snapshot: UsageSnapshot?)]
    ) -> Room? {
        guard let urgency, urgency > nearlyOutAbove else { return nil }
        return others
            .filter { $0.account.accountID != accountID && $0.account.providerID == providerID }
            .compactMap { entry -> Room? in
                guard let used = AccountOrder.urgency(of: entry.snapshot), used < roomBelow else { return nil }
                return Room(accountID: entry.account.accountID, name: entry.account.displayName, freePct: 100 - used)
            }
            .max { $0.freePct < $1.freePct }
    }

    /// "Work has 70% free", the line under a card.
    static func roomLine(_ room: Room) -> String {
        String(localized: "\(room.name) has \(Int(room.freePct))% free")
    }

    /// "Work has 70% free.", the sentence a limit alert ends with.
    static func roomSentence(_ room: Room) -> String {
        String(localized: "\(room.name) has \(Int(room.freePct))% free.")
    }
}
