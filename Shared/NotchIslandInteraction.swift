import Foundation

/// The notch island's open level from the cursor and the clicks, as a
/// pure state machine: the controller feeds it events and arms whatever
/// timer it asks for, nothing more. Pure so the hover-intent dwell, the
/// expand dwell, the leave delay, the click toggle and the click-outside
/// close are unit-tested rather than reproduced by hand under a notch.
///
/// Rules: the cursor has to stay on the island for `dwell` before the
/// wings open (so passing over the notch on the way to a menu does
/// nothing); staying on the open wings for `expand` more opens everything,
/// as does a click at any time; leaving collapses after `leave` whatever
/// opened it; a click anywhere else closes it. The island never takes
/// keyboard focus, so there is no Esc.
struct NotchIslandInteraction: Equatable {
    enum Level: Int, Comparable {
        /// The bare notch (or the pill with its row).
        case collapsed
        /// The wings beside the notch, with the chosen windows' figures.
        case peek
        /// Every account, the full lines, the footer.
        case expanded
        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Event: Equatable {
        case entered
        case left
        case dwellElapsed
        case expandElapsed
        case leaveElapsed
        case tapped
        case clickedOutside
    }

    /// The one timer the controller should have armed after an event;
    /// arming replaces whatever was pending, `.none` cancels it.
    enum Timer: Equatable { case none, dwell, expand, leave }

    static let dwell: Duration = .milliseconds(250)
    static let expand: Duration = .milliseconds(1000)
    /// Short, like boring.notch's: the slab is one contiguous shape, so
    /// moving from a wing into the body never leaves it, and a cursor
    /// that does leave means the user is done.
    static let leave: Duration = .milliseconds(150)

    private(set) var level: Level = .collapsed
    private(set) var isInside = false
    private(set) var timer: Timer = .none
    /// `Preferences.notchIslandExpandsOnHover`; off, only a click opens.
    var peeksOnHover = true

    mutating func handle(_ event: Event) {
        switch event {
        case .entered:
            isInside = true
            guard peeksOnHover else { timer = .none; return }
            switch level {
            case .collapsed: timer = .dwell
            case .peek: timer = .expand
            case .expanded: timer = .none
            }
        case .left:
            isInside = false
            timer = level > .collapsed ? .leave : .none
        case .dwellElapsed:
            timer = .none
            guard isInside, level == .collapsed, peeksOnHover else { return }
            level = .peek
            timer = .expand
        case .expandElapsed:
            timer = .none
            guard isInside, level == .peek, peeksOnHover else { return }
            level = .expanded
        case .leaveElapsed:
            timer = .none
            guard !isInside else { return }
            level = .collapsed
        case .tapped:
            isInside = true
            timer = .none
            level = level == .expanded ? .collapsed : .expanded
        case .clickedOutside:
            isInside = false
            timer = .none
            level = .collapsed
        }
    }

    /// Opened by something other than the user (the first-run reveal):
    /// shown as the peek, closed by the usual leave or click rules; it
    /// does not expand on its own.
    mutating func reveal() {
        guard level == .collapsed else { return }
        level = .peek
        timer = .none
    }

    mutating func collapse() {
        level = .collapsed
        timer = .none
    }
}
