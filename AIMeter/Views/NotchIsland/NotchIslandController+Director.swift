#if os(macOS) && DEBUG
import AppKit

extension NotchIslandController {
    /// `DEBUG` only (`IslandDirector`): the island at `level` as if the
    /// cursor had opened it, with no cursor anywhere near, for the website's
    /// videos. The level's own rules still apply from there: a click
    /// outside closes it.
    func direct(_ level: NotchIslandInteraction.Level) {
        state.isRevealing = false
        switch level {
        case .collapsed:
            interaction.collapse()
            if state.isHovering { state.isHovering = false }
        case .peek:
            interaction.collapse()
            interaction.reveal()
            if !state.isHovering { state.isHovering = true }
        case .expanded:
            if interaction.level != .expanded { interaction.handle(.tapped) }
            if !state.isHovering { state.isHovering = true }
        }
        levelChanged()
    }
}
#endif
