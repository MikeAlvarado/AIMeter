import SwiftUI
import AppKit

/// The two landscape product-page assets App Store Connect added with
/// iOS 26: the header (shown above the product page, 5244×2950 or
/// 3840×1646) and the search-results card (5244×2950, 3840×2560 or
/// 1920×1280). Same language as the screenshot frames — dark warm
/// backdrop, one headline, the real app in a bezel — laid out
/// landscape: copy on the left, device on the right, everything kept
/// inside the central two thirds because the store crops the edges on
/// smaller screens.
enum MarketingKind {
    case header, search

    var pixels: CGSize { self == .header ? CGSize(width: 5244, height: 2950) : CGSize(width: 3840, height: 2560) }
    var scale: CGFloat { 3 }
    var canvas: CGSize { CGSize(width: pixels.width / scale, height: pixels.height / scale) }
}

struct DeviceBezel: View {
    let image: NSImage
    let screenW: CGFloat
    var bezel: CGFloat = 11
    var outerRadius: CGFloat = 60
    var innerRadius: CGFloat = 50
    var tilt: Double = -4

    var body: some View {
        let screenH = screenW * image.size.height / image.size.width
        ZStack {
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .fill(Color(hex: 0x0E0D0C))
                .frame(width: screenW + 2 * bezel, height: screenH + 2 * bezel)
                .overlay(
                    RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1.5)
                )
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: screenW, height: screenH)
                .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
        }
        .shadow(color: .black.opacity(0.55), radius: 36, y: 28)
        .rotationEffect(.degrees(tilt))
    }
}

struct MarketingFrame: View {
    let kind: MarketingKind
    let headline: String
    let subhead: String
    let phone: NSImage
    let widgets: NSImage?

    var body: some View {
        let c = kind.canvas
        let headlineSize: CGFloat = kind == .header ? 108 : 74
        let subheadSize: CGFloat = kind == .header ? 40 : 30
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x221D19), Color(hex: 0x3D2B22), Color(hex: 0x14110F)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(hex: 0xD97757).opacity(0.30), .clear],
                center: .center, startRadius: 0, endRadius: c.height * 0.9
            )
            .offset(x: c.width * 0.18, y: c.height * 0.1)

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: kind == .header ? 26 : 20) {
                    Text(headline)
                        .font(.system(size: headlineSize, weight: .bold))
                        .foregroundStyle(Color(hex: 0xFAF9F5))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subhead)
                        .font(.system(size: subheadSize))
                        .foregroundStyle(Color(hex: 0xFAF9F5).opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        pill("Free")
                        pill("Open source")
                        pill("No account")
                    }
                    .padding(.top, 6)
                }
                .frame(width: c.width * 0.35, alignment: .leading)
                .padding(.leading, c.width * 0.13)

                Spacer(minLength: 0)

                // Device zone: the phone sits low and right, the widget
                // cluster floats high and left of it, nothing crossing into
                // the copy column.
                ZStack {
                    DeviceBezel(image: phone, screenW: c.height * 0.44, tilt: -5)
                        .offset(x: c.height * 0.10, y: c.height * 0.14)
                    if let widgets {
                        Image(nsImage: widgets)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: c.height * 0.46, height: c.height * 0.46 * widgets.size.height / widgets.size.width)
                            .rotationEffect(.degrees(-5))
                            .offset(x: -c.height * 0.10, y: -c.height * 0.16)
                    }
                }
                .frame(width: c.width * 0.40)
                .padding(.trailing, c.width * 0.11)
            }
        }
        .frame(width: c.width, height: c.height)
        .clipped()
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: kind == .header ? 28 : 22, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(Color(hex: 0xE08B6D))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Color(hex: 0xE08B6D).opacity(0.14), in: Capsule())
    }
}

@MainActor
func renderMarketing(rawDir: String, outDir: String, widgets: NSImage?) {
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    guard let phone = NSImage(contentsOfFile: rawDir + "/dashboard.png") else { print("missing dashboard.png"); return }
    let specs: [(MarketingKind, String)] = [(.header, "header-5244x2950"), (.search, "search-3840x2560")]
    for (kind, name) in specs {
        NSAppearance.current = NSAppearance(named: .darkAqua)
        let view = MarketingFrame(
            kind: kind,
            headline: "All your AI limits,\none glance.",
            subhead: "Session, weekly and per-model windows, widgets, alerts and history. On iPhone, iPad and your Mac's menu bar.",
            phone: phone, widgets: widgets
        ).environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: view); r.scale = kind.scale
        guard let cg = r.cgImage else { print("render failed", name); continue }
        let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png"))
        print("wrote \(name) \(cg.width)x\(cg.height)")
    }
}
