import Foundation
import UsageKit

/// What a pet drawn once, rather than on the pets' clock, is up to: the
/// account's pet in its Session Live Activity (see "Live Activity" in
/// `AIMeterWidgets/CLAUDE.md`), which WidgetKit draws at each update and
/// then leaves still. Read from the figure and the window's flag when the
/// activity draws, so its `ContentState` carries nothing new. It never
/// sleeps: asleep at the reset would take an update at the reset, which
/// nothing can send with no server (the system doesn't redraw an activity
/// when its stale date passes, measured on iOS 27), and the next refresh
/// ends the activity anyway.
enum SessionPetMood: Hashable, Sendable {
    /// Room to spare: standing.
    case calm
    /// Past 70 %, or flagged by the provider: fidgeting beside a yellow "!".
    case nearLimit
    /// Past 85 %, or critical: the same beside a red "!".
    case almostOut

    /// The levels are the bars' (`UsageLevel`), so the pet gets nervous
    /// exactly where a bar turns yellow, and the usage-colors switch only
    /// takes the "!" its color, never the mood.
    init(usedPct: Double, severity: UsageWindow.Severity?) {
        switch UsageLevel(usedPct: usedPct, severity: severity) {
        case .normal: self = .calm
        case .warning: self = .nearLimit
        case .danger: self = .almostOut
        }
    }

    var pose: SessionPet.Pose {
        switch self {
        case .calm: .working
        case .nearLimit, .almostOut: .waiting
        }
    }
}

extension SessionPet {
    /// An account's own pet, from its id the way a session's comes from
    /// its own: the same on every launch and on every device.
    init(accountID: String) {
        self.init(index: Self.naturalIndex(for: accountID))
    }

    /// The pixels as they end up painted: where two land on one spot (the
    /// sunglasses over an eye, a hat over the ears), only the later one,
    /// the one that shows. A still frame can then be filled a tone at a
    /// time, in any order.
    func paintedPixels(pose: Pose, tick: Int) -> [Pixel] {
        var painted: [Int: Pixel] = [:]
        for pixel in pixels(pose: pose, tick: tick) {
            painted[pixel.y * Self.canvasWidth + pixel.x] = pixel
        }
        return painted.keys.sorted().compactMap { painted[$0] }
    }

    /// The pets' "!", in its two-pixel column: four rows, a gap, the dot.
    static let alertRows = [0, 1, 2, 3, 5]
}
