#if os(macOS)
import SwiftUI

/// A session's pixel pet (`SessionPet`), painted from its pixels on the
/// pets' shared clock, so every pet on screen steps together. The clock
/// runs only while a pet is shown, which is only while a session works,
/// waits or just finished; under Reduce Motion the pet stands still. A
/// soft glow in its own color, like Vibe Island's pets: on the island's
/// black a pet reads lit rather than pasted on.
struct PixelPetView: View {
    let pet: SessionPet
    let pose: SessionPet.Pose
    /// Points per sprite pixel (`SessionPet.pixelSize`).
    let pixel: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                PetCanvas(pet: pet, pose: pose, tick: 0, pixel: pixel)
            } else {
                TimelineView(.periodic(from: SessionPet.epoch, by: SessionPet.tickInterval)) { context in
                    PetCanvas(pet: pet, pose: pose, tick: SessionPet.tick(at: context.date), pixel: pixel)
                }
            }
        }
        .frame(width: CGFloat(SessionPet.canvasWidth) * pixel, height: CGFloat(SessionPet.canvasHeight) * pixel)
        .offset(y: -CGFloat(SessionPet.bodyLift) * pixel)
        .shadow(color: Color(hex: pet.palette.hex.body).opacity(0.75), radius: 1.5 * pixel)
        .accessibilityHidden(true)
    }
}

private struct PetCanvas: View {
    let pet: SessionPet
    let pose: SessionPet.Pose
    let tick: Int
    let pixel: CGFloat

    var body: some View {
        Canvas { context, _ in
            let tones = PetTones(pet.palette)
            for dot in pet.pixels(pose: pose, tick: tick) {
                let square = CGRect(x: CGFloat(dot.x) * pixel, y: CGFloat(dot.y) * pixel, width: pixel, height: pixel)
                context.fill(Path(square), with: .color(tones.color(dot.tone)))
            }
        }
    }
}

/// The pets' colors: their palette's three stops, and the accessories'
/// neutrals, which read on any body and on the island's black.
private struct PetTones {
    let body: Color
    let light: Color
    let dark: Color

    init(_ palette: SessionPet.Palette) {
        body = Color(hex: palette.hex.body)
        light = Color(hex: palette.hex.light)
        dark = Color(hex: palette.hex.dark)
    }

    func color(_ tone: SessionPet.Tone) -> Color {
        switch tone {
        case .body: body
        case .light: light
        case .dark: dark
        case .white: Color(hex: 0xF2F1EC)
        case .gray: Color(hex: 0x8C8B84)
        case .lightGray: Color(hex: 0xD3D1C7)
        case .black: Color(hex: 0x121212)
        }
    }
}

/// The yellow "!" of a pet waiting for a permission prompt, in the pets'
/// pixels: beside the pet rather than over its head, so it always stays
/// inside the island's bar. It hops on the shared clock.
struct PixelAlertView: View {
    let pixel: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                mark(up: false)
            } else {
                TimelineView(.periodic(from: SessionPet.epoch, by: SessionPet.tickInterval)) { context in
                    mark(up: (SessionPet.tick(at: context.date) / 4) % 2 != 0)
                }
            }
        }
        .frame(width: 2 * pixel, height: 7 * pixel)
        .accessibilityHidden(true)
    }

    private func mark(up: Bool) -> some View {
        Canvas { context, _ in
            let top: CGFloat = up ? 0 : 1
            for row in [0, 1, 2, 3, 5] {
                let square = CGRect(x: 0, y: (top + CGFloat(row)) * pixel, width: 2 * pixel, height: pixel)
                context.fill(Path(square), with: .color(Theme.islandWarning))
            }
        }
    }
}

/// Pets side by side, a waiting one with its "!" after it. On the live
/// island a click on any pet but the lead's puts its session in the sneak
/// (`NotchIslandActions.pickSession`); a click on the lead's opens the
/// island, like one anywhere else on it.
struct PetGroup: View {
    let slots: [NotchIslandModel.Sessions.PetSlot]
    let pixel: CGFloat
    /// The session the sneak shows now.
    var leadID: String?
    @Environment(\.notchIslandActions) private var actions

    var body: some View {
        HStack(spacing: 4 * pixel) {
            ForEach(slots) { slot in
                let pet = HStack(spacing: pixel) {
                    PixelPetView(pet: slot.pet, pose: slot.pose, pixel: pixel)
                    if slot.pose == .waiting {
                        PixelAlertView(pixel: pixel)
                    }
                }
                if let actions, slot.id != leadID {
                    pet
                        .contentShape(Rectangle())
                        .onTapGesture { actions.pickSession(slot.id) }
                } else {
                    pet
                }
            }
        }
        .fixedSize()
    }
}
#endif
