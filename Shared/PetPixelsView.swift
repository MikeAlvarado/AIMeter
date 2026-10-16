import SwiftUI

extension SessionPet {
    /// A tone's color: the palette's three stops for the body, and the
    /// accessories' neutrals, which read on any body, on the island's black
    /// and on a light card.
    func color(_ tone: Tone) -> Color {
        switch tone {
        case .body: Color(hex: palette.hex.body)
        case .light: Color(hex: palette.hex.light)
        case .dark: Color(hex: palette.hex.dark)
        case .white: Color(hex: 0xF2F1EC)
        case .gray: Color(hex: 0x8C8B84)
        case .lightGray: Color(hex: 0xD3D1C7)
        case .black: Color(hex: 0x121212)
        }
    }
}

/// A pet in one still frame (`SessionPet.paintedPixels`), a path per tone:
/// for a surface drawn once instead of on the pets' clock, like the
/// Session Live Activity, which WidgetKit renders as an archived
/// snapshot. The island's pets, which walk, are `PixelPetView`.
struct PetPixelsView: View {
    let pet: SessionPet
    let pose: SessionPet.Pose
    /// Points per sprite pixel (`SessionPet.pixelSize`).
    let pixel: CGFloat

    var body: some View {
        let byTone = Dictionary(grouping: pet.paintedPixels(pose: pose, tick: 0), by: \.tone)
        ZStack(alignment: .topLeading) {
            ForEach(SessionPet.Tone.allCases, id: \.self) { tone in
                if let dots = byTone[tone] {
                    Path { path in
                        for dot in dots {
                            path.addRect(CGRect(x: CGFloat(dot.x) * pixel, y: CGFloat(dot.y) * pixel, width: pixel, height: pixel))
                        }
                    }
                    .fill(pet.color(tone))
                }
            }
        }
        .frame(
            width: CGFloat(SessionPet.canvasWidth) * pixel,
            height: CGFloat(SessionPet.canvasHeight) * pixel,
            alignment: .topLeading
        )
        .accessibilityHidden(true)
    }
}

/// The pets' "!" standing still, in whatever color the surface gives it.
struct PetAlertMark: View {
    let pixel: CGFloat
    let color: Color

    var body: some View {
        Path { path in
            for row in SessionPet.alertRows {
                path.addRect(CGRect(x: 0, y: CGFloat(row) * pixel, width: 2 * pixel, height: pixel))
            }
        }
        .fill(color)
        .frame(width: 2 * pixel, height: CGFloat((SessionPet.alertRows.last ?? 0) + 1) * pixel)
        .accessibilityHidden(true)
    }
}
