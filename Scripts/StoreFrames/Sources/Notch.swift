import SwiftUI
import AppKit

/// The notch island frames: not store assets (the Mac app is not in the
/// store) but the same language as the screenshot frames — the dark warm
/// backdrop, one short claim, the capture in a bezel — at 16:9 for the
/// website and for posts. Input is the three `island-*.png` files
/// `site/scripts/island.mjs` leaves in its work dir (see CLAUDE.md →
/// "Not store assets").
struct NotchFrame: View {
    static let canvas = CGSize(width: 1200, height: 675)
    let headline: String
    let subhead: String
    let expanded: NSImage
    let peek: NSImage?

    var body: some View {
        let c = Self.canvas
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x221D19), Color(hex: 0x3D2B22), Color(hex: 0x14110F)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(hex: 0xD97757).opacity(0.30), .clear],
                center: .center, startRadius: 0, endRadius: c.height * 0.9
            )
            .offset(x: peek == nil ? c.width * 0.18 : 0, y: peek == nil ? c.height * 0.1 : -c.height * 0.2)

            if let peek {
                // Text on top, the two states stacked under it.
                VStack(spacing: 28) {
                    copy(alignment: .center, width: c.width * 0.7)
                    VStack(spacing: 18) {
                        DeviceBezel(image: peek, screenW: c.width * 0.52, bezel: 6, outerRadius: 22, innerRadius: 16, tilt: 0)
                        DeviceBezel(image: expanded, screenW: c.width * 0.52, bezel: 6, outerRadius: 22, innerRadius: 16, tilt: 0)
                    }
                }
                .padding(.top, 40)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                // Copy on the left, the expanded island on the right.
                HStack(spacing: 0) {
                    copy(alignment: .leading, width: c.width * 0.36)
                        .padding(.leading, c.width * 0.08)
                    Spacer(minLength: 0)
                    DeviceBezel(image: expanded, screenW: c.width * 0.46, bezel: 8, outerRadius: 28, innerRadius: 20, tilt: -3)
                        .padding(.trailing, c.width * 0.06)
                }
            }
        }
        .frame(width: c.width, height: c.height)
        .clipped()
    }

    private func copy(alignment: HorizontalAlignment, width: CGFloat) -> some View {
        VStack(alignment: alignment, spacing: 18) {
            Text(headline)
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(Color(hex: 0xFAF9F5))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(subhead)
                .font(.system(size: 23))
                .foregroundStyle(Color(hex: 0xFAF9F5).opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                pill("Mac")
                pill("Free")
                pill("Open source")
            }
            .padding(.top, 4)
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .frame(width: width, alignment: alignment == .center ? .center : .leading)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(Color(hex: 0xE08B6D))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color(hex: 0xE08B6D).opacity(0.14), in: Capsule())
    }
}

@MainActor
func renderNotch(islandDir: String, outDir: String) {
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    guard let expanded = NSImage(contentsOfFile: islandDir + "/island-expanded.png"),
          let peek = NSImage(contentsOfFile: islandDir + "/island-peek.png") else {
        print("missing island-expanded.png / island-peek.png in", islandDir); return
    }
    let specs: [(String, NotchFrame)] = [
        ("notch-01-island", NotchFrame(
            headline: "Your limits,\nin the notch.",
            subhead: "Rest the cursor on your MacBook’s notch and your figures appear beside it. Stay, or click, and every account opens.",
            expanded: expanded, peek: nil)),
        ("notch-02-peek", NotchFrame(
            headline: "A peek, then everything.",
            subhead: "A glance beside the notch; a second more, or a click, for every account, every window and every reset.",
            expanded: expanded, peek: peek)),
    ]
    for (name, frame) in specs {
        NSAppearance.current = NSAppearance(named: .darkAqua)
        let r = ImageRenderer(content: frame.environment(\.colorScheme, .dark)); r.scale = 2
        guard let cg = r.cgImage else { print("render failed", name); continue }
        let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png"))
        print("wrote \(name) \(cg.width)x\(cg.height)")
    }
}
