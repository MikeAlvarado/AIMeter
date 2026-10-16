import Foundation

/// The notch island's open level from the cursor and the clicks, as a
/// pure state machine: the controller feeds it events and arms whatever
/// timer it asks for, nothing more. Pure so the hover-intent dwell, the
/// leave delay, the click that opens it and the click-outside close are
/// unit-tested rather than reproduced by hand under a notch.
///
/// Rules: the cursor has to stay on the island for `dwell` before the
/// wings open (so passing over the notch on the way to a menu does
/// nothing); only a click opens everything, and a click on the open
/// island leaves it open, so the rows inside can be clicked (the
/// controls that open the app or Settings close it, `closed`); leaving
/// collapses after `leave` whatever opened it; a click anywhere else
/// closes it. Where the collapsed island already shows the row the wings
/// would (`skipsPeek`), resting on it adds nothing, so only a click opens
/// it. The island never takes keyboard focus, so there is no Esc.
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
        case leaveElapsed
        case tapped
        /// A control on the open island opened the app, Settings or
        /// another of its windows, where the user is going next.
        case closed
        case clickedOutside
    }

    /// The one timer the controller should have armed after an event;
    /// arming replaces whatever was pending, `.none` cancels it.
    enum Timer: Equatable { case none, dwell, leave }

    /// The default hover-intent dwell. The user can change it
    /// (`Preferences.notchIslandHoverDelay`, 0–1 s, boring.notch's "hover
    /// delay"); the controller arms `.dwell` with that value.
    static let dwell: Duration = .milliseconds(250)
    static let defaultDwellSeconds: Double = 0.25
    static let dwellRange: ClosedRange<Double> = 0...1
    /// Short, like boring.notch's: the slab is one contiguous shape, so
    /// moving from a wing into the body never leaves it, and a cursor
    /// that does leave means the user is done.
    static let leave: Duration = .milliseconds(150)

    /// A stored hover delay as a usable one: inside `dwellRange`, and a
    /// non-number (a corrupt write) is the default rather than a timer
    /// that never fires.
    static func clampedDwell(seconds: Double) -> Double {
        guard seconds.isFinite else { return defaultDwellSeconds }
        return min(max(seconds, dwellRange.lowerBound), dwellRange.upperBound)
    }

    static func dwell(seconds: Double) -> Duration {
        .milliseconds(Int((clampedDwell(seconds: seconds) * 1000).rounded()))
    }

    private(set) var level: Level = .collapsed
    private(set) var isInside = false
    private(set) var timer: Timer = .none
    /// `Preferences.notchIslandExpandsOnHover`; off, only a click opens.
    var peeksOnHover = true
    /// The collapsed island is already showing its row — a drawn notch or
    /// a pill in sight (`NotchIslandVisibility.showsRowWhenCollapsed`) —
    /// so the peek would show nothing new: resting on it does nothing and
    /// a click opens it. A hidden island keeps the peek, which is what
    /// brings its row back; the first-run reveal still peeks either way.
    var skipsPeek = false

    mutating func handle(_ event: Event) {
        switch event {
        case .entered:
            isInside = true
            timer = level == .collapsed && peeksOnHover && !skipsPeek ? .dwell : .none
        case .left:
            isInside = false
            timer = level > .collapsed ? .leave : .none
        case .dwellElapsed:
            timer = .none
            guard isInside, level == .collapsed, peeksOnHover, !skipsPeek else { return }
            level = .peek
        case .leaveElapsed:
            timer = .none
            guard !isInside else { return }
            level = .collapsed
        case .tapped:
            isInside = true
            timer = .none
            level = .expanded
        case .closed:
            timer = .none
            level = .collapsed
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
