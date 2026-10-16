import Foundation

/// The pets' pixels: each creature drawn by hand on a 12 × 10 grid, the
/// accessories fitted to it (between the cat's ears, over the frog's eyes),
/// and the poses. Everything lands in a 14 × 14 canvas: the body, three
/// rows of headroom for a hat, and a pixel on every side for the steps and
/// the shake; `SessionPetTests` checks every combination stays inside.
extension SessionPet {
    static let canvasWidth = 14
    static let canvasHeight = 14
    private static let originX = 1
    private static let originY = 4
    /// How far the body's center sits below the canvas's, in pixels: the
    /// headroom is all above it. `PixelPetView` draws the pet up by this
    /// much, so the body (not the canvas) is centered on its row and the
    /// hat and the "z" rise into the space above.
    static let bodyLift = originY + 5 - canvasHeight / 2

    enum Tone: CaseIterable, Sendable { case body, light, dark, white, gray, lightGray, black }

    struct Pixel: Equatable, Sendable {
        let x: Int
        let y: Int
        let tone: Tone
    }

    /// The pet at `tick` (`SessionPet.tick(at:)`), in canvas coordinates.
    /// Working, it walks in place: the feet alternate and the body bobs a
    /// pixel every quarter second. Waiting, it shakes from side to side
    /// (the "!" is drawn beside it, `PixelAlertView`, so it never leaves
    /// the island). Asleep, its eyes close and a "z" blinks over it.
    func pixels(pose: Pose, tick: Int) -> [Pixel] {
        let sprite = creature.sprite
        let asleep = pose == .asleep
        let step = pose == .working && (tick / 2) % 2 != 0
        let dx = pose == .waiting ? [0, -1, 0, 1][((tick % 4) + 4) % 4] : 0
        let dy = step ? -1 : 0
        var out: [Pixel] = []
        func put(_ x: Int, _ y: Int, _ tone: Tone) {
            out.append(Pixel(x: x + Self.originX + dx, y: y + Self.originY + dy, tone: tone))
        }
        for (y, row) in sprite.rows.enumerated() {
            for (x, cell) in row.enumerated() {
                switch cell {
                case "X": put(x, y, .body)
                case "L": put(x, y, .light)
                case "D": put(x, y, .dark)
                case "W": put(x, y, asleep ? .body : .light)
                case "E": put(x, y, asleep ? .body : .dark)
                case "e": put(x, y, asleep ? .light : .dark)
                case "a" where !step: put(x, y, .body)
                case "b" where step: put(x, y, .body)
                case "p" where !step: put(x, y, .light)
                case "q" where step: put(x, y, .light)
                default: break
                }
            }
        }
        if asleep {
            for line in sprite.closedEyes {
                for x in line.from...line.to { put(x, line.y, .dark) }
            }
        }
        if pose == .waiting, let mouth = sprite.mouth {
            put(mouth.x, mouth.y, .dark)
            put(mouth.x + 1, mouth.y, .dark)
        }
        for pixel in accessoryPixels(sprite) { put(pixel.x, pixel.y, pixel.tone) }
        if asleep, ((tick % 16) + 16) % 16 < 12 {
            // A three-pixel "z" in the top corner, clear of every hat.
            for (x, y) in [(11, 0), (12, 0), (13, 0), (12, 1), (11, 2), (12, 2), (13, 2)] {
                out.append(Pixel(x: x, y: y, tone: .white))
            }
        }
        return out
    }

    private func accessoryPixels(_ sprite: PetSprite) -> [Pixel] {
        var out: [Pixel] = []
        func span(_ y: Int, _ from: Int, _ to: Int, _ tone: Tone) {
            for x in from...to { out.append(Pixel(x: x, y: y, tone: tone)) }
        }
        switch accessory {
        case .none:
            break
        case .sunglasses:
            for eye in sprite.eyes {
                for y in eye.y..<(eye.y + eye.height) { span(y, eye.x - 1, eye.x + eye.width, .black) }
                out.append(Pixel(x: eye.x - 1, y: eye.y, tone: .white))
            }
            let left = sprite.eyes[0], right = sprite.eyes[1]
            if left.x + left.width + 1 <= right.x - 2 {
                span(left.y, left.x + left.width + 1, right.x - 2, .black)
            }
        case .topHat:
            span(sprite.hat.y, sprite.hat.from - 1, sprite.hat.to + 1, .gray)
            span(sprite.hat.y - 1, sprite.hat.from, sprite.hat.to, .light)
            span(sprite.hat.y - 2, sprite.hat.from, sprite.hat.to, .gray)
            span(sprite.hat.y - 3, sprite.hat.from, sprite.hat.to, .gray)
        case .beanie:
            for row in sprite.beanie { span(row.y, row.from, row.to, .light) }
            span(sprite.cuff.y, sprite.cuff.from, sprite.cuff.to, .white)
            span(sprite.pompom.y, sprite.pompom.from, sprite.pompom.to, .white)
        case .bow:
            for (x, y) in [(0, 0), (4, 0), (0, 1), (1, 1), (3, 1), (4, 1), (0, 2), (4, 2)] {
                out.append(Pixel(x: sprite.bow.x + x, y: sprite.bow.y + y, tone: .white))
            }
            out.append(Pixel(x: sprite.bow.x + 2, y: sprite.bow.y + 1, tone: .lightGray))
        case .headphones:
            for row in sprite.band { span(row.y, row.from, row.to, .lightGray) }
            for dot in sprite.bandDots { out.append(Pixel(x: dot.x, y: dot.y, tone: .lightGray)) }
            for cup in sprite.cups {
                for y in cup.y..<(cup.y + 3) { span(y, cup.x, cup.x + 1, .gray) }
            }
        }
        return out
    }
}

extension SessionPet.Palette {
    /// The body, its light (highlights, inner ears, a muzzle) and its dark
    /// (eyes, a nose): the stops of one ramp.
    var hex: (body: UInt32, light: UInt32, dark: UInt32) {
        switch self {
        case .blue: (0x378ADD, 0xB5D4F4, 0x042C53)
        case .purple: (0x7F77DD, 0xCECBF6, 0x26215C)
        case .green: (0x1D9E75, 0x9FE1CB, 0x04342C)
        case .pink: (0xD4537E, 0xF4C0D1, 0x4B1528)
        case .orange: (0xD85A30, 0xF5C4B3, 0x4A1B0C)
        case .lime: (0x639922, 0xC0DD97, 0x173404)
        }
    }
}

/// One creature: its rows (X body, L light, W an eye's light and E a pupil,
/// both gone when asleep, e a pupil on a pale face, gone to the light, D
/// dark, a and b the feet's two steps, p and q the same feet in the light)
/// and where each accessory sits on it.
struct PetSprite: Sendable {
    struct Span: Sendable { let y: Int; let from: Int; let to: Int }
    struct Spot: Sendable { let x: Int; let y: Int }
    struct Eye: Sendable { let x: Int; let y: Int; let width: Int; let height: Int }

    let rows: [String]
    let closedEyes: [Span]
    /// Where a worried mouth opens while waiting, when the face has room.
    var mouth: Spot?
    let eyes: [Eye]
    /// The brim's row and the crown's columns.
    let hat: Span
    let beanie: [Span]
    let cuff: Span
    let pompom: Span
    let bow: Spot
    let band: [Span]
    let bandDots: [Spot]
    let cups: [Spot]
}

extension SessionPet.Creature {
    var sprite: PetSprite {
        switch self {
        case .drop:
            PetSprite(rows: [".....XX.....", "....XXXX....", "...XXXXXX...", "..XLLXXXXX..", ".XXLXXXXXXX.",
                          ".XXEXXXXEXX.", "XXXEXXXXEXXX", "XXXXXXXXXXXX", "XXXXXXXXXXXX", "bXXXXXXXXXXb"],
                   closedEyes: [.init(y: 6, from: 3, to: 4), .init(y: 6, from: 7, to: 8)], mouth: .init(x: 5, y: 7),
                   eyes: [.init(x: 3, y: 5, width: 1, height: 2), .init(x: 8, y: 5, width: 1, height: 2)],
                   hat: .init(y: 1, from: 4, to: 7), beanie: [.init(y: 0, from: 5, to: 6), .init(y: 1, from: 4, to: 7)],
                   cuff: .init(y: 2, from: 3, to: 8), pompom: .init(y: -1, from: 5, to: 6), bow: .init(x: 6, y: 0),
                   band: [.init(y: -1, from: 4, to: 7)],
                   bandDots: [.init(x: 3, y: 0), .init(x: 8, y: 0), .init(x: 2, y: 1), .init(x: 9, y: 1), .init(x: 2, y: 2), .init(x: 9, y: 2)],
                   cups: [.init(x: 1, y: 3), .init(x: 9, y: 3)])
        case .ghost:
            PetSprite(rows: ["....XXXX....", "..XXXXXXXX..", ".XLLXXXXXXX.", ".XLXXXXXXXX.", "XXXEXXXXEXXX",
                          "XXXEXXXXEXXX", "XXXXXXXXXXXX", "XXXXXXXXXXXX", "XXXXXXXXXXXX", "XXa.bXXb.aXX"],
                   closedEyes: [.init(y: 5, from: 3, to: 4), .init(y: 5, from: 7, to: 8)], mouth: .init(x: 5, y: 6),
                   eyes: [.init(x: 3, y: 4, width: 1, height: 2), .init(x: 8, y: 4, width: 1, height: 2)],
                   hat: .init(y: 0, from: 4, to: 7), beanie: [.init(y: -1, from: 5, to: 6), .init(y: 0, from: 4, to: 7)],
                   cuff: .init(y: 1, from: 3, to: 8), pompom: .init(y: -2, from: 5, to: 6), bow: .init(x: 7, y: -1),
                   band: [.init(y: -1, from: 3, to: 8)],
                   bandDots: [.init(x: 2, y: 0), .init(x: 9, y: 0), .init(x: 1, y: 1), .init(x: 10, y: 1), .init(x: 0, y: 2), .init(x: 11, y: 2)],
                   cups: [.init(x: 0, y: 3), .init(x: 10, y: 3)])
        case .cat:
            PetSprite(rows: [".X........X.", ".XX......XX.", ".XLXXXXXXLX.", ".XXXXXXXXXX.", "XXXEXXXXEXXX",
                          "XXXEXXXXEXXX", "XXXXXDDXXXXX", ".XXXXXXXXXX.", "..XXXXXXXX..", "..aXb..bXa.."],
                   closedEyes: [.init(y: 5, from: 3, to: 4), .init(y: 5, from: 7, to: 8)],
                   eyes: [.init(x: 3, y: 4, width: 1, height: 2), .init(x: 8, y: 4, width: 1, height: 2)],
                   hat: .init(y: 2, from: 4, to: 7), beanie: [.init(y: 0, from: 4, to: 7), .init(y: 1, from: 3, to: 8)],
                   cuff: .init(y: 2, from: 3, to: 8), pompom: .init(y: -1, from: 5, to: 6), bow: .init(x: 7, y: 0),
                   band: [.init(y: -1, from: 1, to: 10)],
                   bandDots: [.init(x: 0, y: 0), .init(x: 11, y: 0), .init(x: 0, y: 1), .init(x: 11, y: 1), .init(x: 0, y: 2), .init(x: 11, y: 2)],
                   cups: [.init(x: 0, y: 3), .init(x: 10, y: 3)])
        case .bunny:
            PetSprite(rows: ["..XX....XX..", "..XL....LX..", "..XL....LX..", "..XX....XX..", ".XXXXXXXXXX.",
                          "XXXEXXXXEXXX", "XXXXXDDXXXXX", "XXXXXXXXXXXX", ".XXXXXXXXXX.", "..aXb..bXa.."],
                   closedEyes: [.init(y: 5, from: 3, to: 4), .init(y: 5, from: 7, to: 8)],
                   eyes: [.init(x: 3, y: 5, width: 1, height: 1), .init(x: 8, y: 5, width: 1, height: 1)],
                   hat: .init(y: 3, from: 5, to: 6), beanie: [.init(y: 2, from: 5, to: 6), .init(y: 3, from: 4, to: 7)],
                   cuff: .init(y: 4, from: 3, to: 8), pompom: .init(y: 1, from: 5, to: 6), bow: .init(x: 7, y: 0),
                   band: [.init(y: -1, from: 2, to: 9)],
                   bandDots: [.init(x: 1, y: 0), .init(x: 10, y: 0), .init(x: 1, y: 1), .init(x: 10, y: 1), .init(x: 1, y: 2),
                              .init(x: 10, y: 2), .init(x: 0, y: 3), .init(x: 11, y: 3)],
                   cups: [.init(x: 0, y: 4), .init(x: 10, y: 4)])
        case .frog:
            PetSprite(rows: ["............", "..XX....XX..", ".XWEX..XEWX.", "XXXXXXXXXXXX", "XXXXXXXXXXXX",
                          "XXDXXXXXXDXX", "XXXDDDDDDXXX", "XXXXXXXXXXXX", ".XXXXXXXXXX.", "aXb......bXa"],
                   closedEyes: [.init(y: 2, from: 2, to: 3), .init(y: 2, from: 8, to: 9)],
                   eyes: [.init(x: 2, y: 2, width: 2, height: 1), .init(x: 8, y: 2, width: 2, height: 1)],
                   hat: .init(y: 2, from: 5, to: 6), beanie: [.init(y: 1, from: 5, to: 6), .init(y: 2, from: 5, to: 6)],
                   cuff: .init(y: 3, from: 4, to: 7), pompom: .init(y: 0, from: 5, to: 6), bow: .init(x: 7, y: 0),
                   band: [.init(y: 0, from: 2, to: 9)],
                   bandDots: [.init(x: 1, y: 1), .init(x: 10, y: 1), .init(x: 0, y: 2), .init(x: 11, y: 2)],
                   cups: [.init(x: 0, y: 3), .init(x: 10, y: 3)])
        case .fox:
            PetSprite(rows: [".D........D.", ".XX......XX.", ".XXXXXXXXXX.", "XXXXXXXXXXXX", "XXXEXXXXEXXX",
                          "LLXEXXXXEXLL", ".LLLXXXXLLL.", "..LLLDDLLL..", "...LLLLLL...", "...ab..ba..."],
                   closedEyes: [.init(y: 5, from: 3, to: 4), .init(y: 5, from: 7, to: 8)],
                   eyes: [.init(x: 3, y: 4, width: 1, height: 2), .init(x: 8, y: 4, width: 1, height: 2)],
                   hat: .init(y: 2, from: 4, to: 7), beanie: [.init(y: 0, from: 4, to: 7), .init(y: 1, from: 3, to: 8)],
                   cuff: .init(y: 2, from: 3, to: 8), pompom: .init(y: -1, from: 5, to: 6), bow: .init(x: 7, y: 0),
                   band: [.init(y: -1, from: 1, to: 10)],
                   bandDots: [.init(x: 0, y: 0), .init(x: 11, y: 0), .init(x: 0, y: 1), .init(x: 11, y: 1), .init(x: 0, y: 2), .init(x: 11, y: 2)],
                   cups: [.init(x: 0, y: 3), .init(x: 10, y: 3)])
        case .axolotl:
            // A pale face and the gills in the body's color, three fronds a
            // side, the way an axolotl is drawn (Mike's pick, 2026-10-16):
            // small eyes far apart and a wide smile.
            PetSprite(rows: ["X..........X", ".X..LLLL..X.", "XX.LLLLLL.XX", "..LeLLLLeL..", "XXLeLLLLeLXX",
                          ".LLLLLLLLLL.", ".LLDLLLLDLL.", "..LLDDDDLL..", "..LLLLLLLL..", "..pLq..qLp.."],
                   closedEyes: [.init(y: 4, from: 3, to: 4), .init(y: 4, from: 7, to: 8)],
                   eyes: [.init(x: 3, y: 3, width: 1, height: 2), .init(x: 8, y: 3, width: 1, height: 2)],
                   // The beanie sits a row higher than on a body-colored head,
                   // as the ghost's does: its crown is the face's own tone.
                   hat: .init(y: 1, from: 4, to: 7), beanie: [.init(y: -1, from: 4, to: 7), .init(y: 0, from: 3, to: 8)],
                   cuff: .init(y: 1, from: 3, to: 8), pompom: .init(y: -2, from: 5, to: 6), bow: .init(x: 4, y: -1),
                   band: [.init(y: 0, from: 3, to: 8)],
                   bandDots: [.init(x: 2, y: 1), .init(x: 9, y: 1), .init(x: 1, y: 2), .init(x: 10, y: 2)],
                   cups: [.init(x: 0, y: 3), .init(x: 10, y: 3)])
        }
    }
}
