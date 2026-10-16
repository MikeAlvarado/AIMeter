#if os(iOS)
import SwiftUI
import UsageKit

/// The account's pet in its Session Live Activity, when it has one
/// (`SessionActivityAttributes.pet`): one still frame, since WidgetKit
/// draws an activity at each update and never on the pets' clock. Its
/// mood (`SessionPetMood`) comes from the figure and the window's flag,
/// and the system animates a change of mood from one update to the next:
/// the new pose pushes up from below, a little hop. See "Live Activity" in
/// this target's CLAUDE.md.
struct ActivityPetView: View {
    let pet: SessionPet
    let mood: SessionPetMood
    /// The height its canvas fits in, on whole device pixels
    /// (`SessionPet.pixelSize`).
    let height: CGFloat
    /// On the Dynamic Island's black. Off it, on the Lock Screen's card,
    /// the pet brings a black tile of its own: its white accessories (a
    /// bow, a beanie's cuff) vanish on a light card, and on black it reads
    /// as the island's pet. A soft glow in its color either way, as on the
    /// Mac's island.
    var onIsland = true
    /// The "!" beside it near the limit; the minimal island has no room.
    var showsMark = true

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let pixel = SessionPet.pixelSize(fitting: height, displayScale: displayScale)
        HStack(spacing: pixel) {
            let frame = PetPixelsView(pet: pet, pose: mood.pose, pixel: pixel)
                .shadow(color: Color(hex: pet.palette.hex.body).opacity(0.75), radius: 1.5 * pixel)
            if onIsland {
                // The body, not the canvas, centered: the canvas keeps a
                // hat's headroom above it.
                frame.offset(y: -CGFloat(SessionPet.bodyLift) * pixel)
            } else {
                frame
                    .padding(pixel)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 3 * pixel, style: .continuous))
            }
            if showsMark, let markColor {
                PetAlertMark(pixel: pixel, color: markColor)
            }
        }
        .id(mood)
        .transition(.push(from: .bottom))
        .accessibilityHidden(true)
    }

    /// Yellow near the limit and red almost out, as the bar turns; with
    /// usage colors off the "!" stays, in the text's own color.
    private var markColor: Color? {
        let usageColors = Preferences.load().usageColors
        switch mood {
        case .calm: return nil
        case .nearLimit: return usageColors ? (onIsland ? Theme.islandWarning : Theme.warning) : Theme.ink
        case .almostOut: return usageColors ? Theme.danger : Theme.ink
        }
    }
}

extension SessionPetMood {
    init(_ state: SessionActivityAttributes.ContentState) {
        self.init(usedPct: state.usedPct, severity: state.severity)
    }
}
#endif
