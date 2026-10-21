#if os(macOS)
import SwiftUI

/// A session's pixel pet (`SessionPet`), painted from its pixels on the
/// pets' shared clock, so every pet on screen steps together. The clock
/// runs only while a pet is shown, which is only while a session works,
/// waits or just finished; under Reduce Motion, or while the Mac is in
/// Low Power Mode (`LowPowerMode`), the pet stands still. A
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
            if !LowPowerMode.petsAnimate(reduceMotion: reduceMotion, lowPower: LowPowerMode.shared.isOn) {
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
            for dot in pet.pixels(pose: pose, tick: tick) {
                let square = CGRect(x: CGFloat(dot.x) * pixel, y: CGFloat(dot.y) * pixel, width: pixel, height: pixel)
                context.fill(Path(square), with: .color(pet.color(dot.tone)))
            }
        }
    }
}

/// The yellow "!" of a pet waiting for a permission prompt, in the pets'
/// pixels: beside the pet rather than over its head, so it always stays
/// inside the island's bar. It hops on the shared clock, and holds still
/// when the pets do.
struct PixelAlertView: View {
    let pixel: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !LowPowerMode.petsAnimate(reduceMotion: reduceMotion, lowPower: LowPowerMode.shared.isOn) {
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
            for row in SessionPet.alertRows {
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
