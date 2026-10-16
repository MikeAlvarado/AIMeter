import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Every session pet in one PNG, from the app's own sprite code
// (`Shared/SessionPet.swift`, `SessionPet+Sprites.swift`), on the island's
// black: a row per creature, in purple, standing, mid-step, waiting and
// asleep, then with each accessory, then standing in each other color.
// Each pet sits on its 14 × 14 canvas, drawn faintly, so a pixel outside
// it shows. `Scripts/pets-preview.sh` builds and runs this; see "A new
// pet" under "Recipes" in the repo-root CLAUDE.md.

let scale = 6
let canvas = SessionPet.canvasWidth * scale
let cell = canvas + 16
let rowLabel = 76
let header = 24
let base = SessionPet.Palette.purple

struct Column {
    let title: String
    let palette: SessionPet.Palette
    let accessory: SessionPet.Accessory
    let pose: SessionPet.Pose
    let tick: Int
}

var columns = [
    Column(title: "stand", palette: base, accessory: .none, pose: .working, tick: 0),
    Column(title: "step", palette: base, accessory: .none, pose: .working, tick: 2),
    Column(title: "wait", palette: base, accessory: .none, pose: .waiting, tick: 0),
    Column(title: "asleep", palette: base, accessory: .none, pose: .asleep, tick: 0),
]
columns += SessionPet.Accessory.allCases.filter { $0 != .none }.map {
    Column(title: "\($0)", palette: base, accessory: $0, pose: .working, tick: 0)
}
columns += SessionPet.Palette.allCases.filter { $0 != base }.map {
    Column(title: "\($0)", palette: $0, accessory: .none, pose: .working, tick: 0)
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// A tone as `PixelPetView` paints it.
func color(_ tone: SessionPet.Tone, _ palette: SessionPet.Palette) -> CGColor {
    switch tone {
    case .body: rgb(palette.hex.body)
    case .light: rgb(palette.hex.light)
    case .dark: rgb(palette.hex.dark)
    case .white: rgb(0xF2F1EC)
    case .gray: rgb(0x8C8B84)
    case .lightGray: rgb(0xD3D1C7)
    case .black: rgb(0x121212)
    }
}

let creatures = SessionPet.Creature.allCases
let width = rowLabel + columns.count * cell
let height = header + creatures.count * cell
guard let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("no context") }
// Top down, like the canvas.
context.translateBy(x: 0, y: CGFloat(height))
context.scaleBy(x: 1, y: -1)
context.setFillColor(rgb(0x000000))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

func label(_ text: String, x: Int, baseline: Int) {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Menlo" as CFString, 11, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(0x9B9A93),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    context.saveGState()
    context.translateBy(x: CGFloat(x), y: CGFloat(baseline))
    context.scaleBy(x: 1, y: -1)
    context.textPosition = .zero
    CTLineDraw(line, context)
    context.restoreGState()
}

for (index, column) in columns.enumerated() {
    label(column.title, x: rowLabel + index * cell + 8, baseline: 16)
}
for (row, creature) in creatures.enumerated() {
    let top = header + row * cell
    label("\(creature)", x: 8, baseline: top + cell / 2 + 4)
    for (index, column) in columns.enumerated() {
        let pet = SessionPet(creature: creature, palette: column.palette, accessory: column.accessory)
        let left = rowLabel + index * cell + (cell - canvas) / 2, y = top + (cell - canvas) / 2
        context.setFillColor(rgb(0x1A1A1A))
        context.fill(CGRect(x: left, y: y, width: canvas, height: canvas))
        for pixel in pet.pixels(pose: column.pose, tick: column.tick) {
            context.setFillColor(color(pixel.tone, column.palette))
            context.fill(CGRect(x: left + pixel.x * scale, y: y + pixel.y * scale, width: scale, height: scale))
        }
    }
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("can't write \(url.path)") }
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print(url.path)
