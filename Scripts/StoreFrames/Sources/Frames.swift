import SwiftUI
import AppKit

/// App Store frame compositor: dark warm backdrop, a headline, and the raw
/// capture inside a tilted device bezel, the way the category's best
/// listings do it. Sizes are exact store sizes: iPhone 6.5" 1242×2688
/// (414×896 pt at 3x), iPad 13" 2064×2752 (1032×1376 pt at 2x).
enum FrameDevice { case phone, pad }

struct FrameSpec {
    let name: String
    let headline: String
    let subhead: String
    let image: String?
    let textOnTop: Bool
    let device: FrameDevice
    var tilt: Double = -4

    var canvas: CGSize { device == .phone ? CGSize(width: 402, height: 874) : CGSize(width: 1032, height: 1376) }
    var scale: CGFloat { device == .phone ? 3 : 2 }
}

struct StoreFrame: View {
    let spec: FrameSpec
    let raw: NSImage?
    let appIcon: NSImage?

    private var phone: Bool { spec.device == .phone }
    private var headlineSize: CGFloat { phone ? 50 : 76 }
    private var subheadSize: CGFloat { phone ? 21 : 31 }
    private var sidePad: CGFloat { phone ? 34 : 90 }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x221D19), Color(hex: 0x3D2B22), Color(hex: 0x14110F)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(hex: 0xD97757).opacity(0.28), .clear],
                center: .center, startRadius: 0, endRadius: spec.canvas.width * 0.85
            )
            .offset(y: spec.textOnTop ? spec.canvas.height * 0.22 : -spec.canvas.height * 0.22)

            if raw == nil {
                closing
            } else {
                // Deterministic anchoring: the device hangs off one edge by a
                // fixed amount and the text sits at the other, so neither
                // can push the other out of the canvas.
                let deviceH = deviceHeight
                let textZone: CGFloat = phone ? 360 : 500
                deviceView
                    .frame(width: spec.canvas.width, height: spec.canvas.height, alignment: spec.textOnTop ? .bottom : .top)
                    .offset(y: spec.textOnTop ? (deviceH - (spec.canvas.height - textZone)) : -(deviceH - (spec.canvas.height - textZone)))
                textBlock
                    .frame(width: spec.canvas.width, height: spec.canvas.height, alignment: spec.textOnTop ? .top : .bottom)
                    .padding(.vertical, 0)
                    .offset(y: spec.textOnTop ? (phone ? 92 : 140) : -(phone ? 92 : 140))
            }
        }
        .frame(width: spec.canvas.width, height: spec.canvas.height)
        .clipped()
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: phone ? 14 : 22) {
            Text(spec.headline)
                .font(.system(size: headlineSize, weight: .bold, design: .default))
                .lineLimit(3)
                .foregroundStyle(Color(hex: 0xFAF9F5))
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
            Text(spec.subhead)
                .font(.system(size: subheadSize, weight: .regular))
                .foregroundStyle(Color(hex: 0xFAF9F5).opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, sidePad)
    }

    private var screenW: CGFloat { phone ? 336 : 860 }
    private var bezel: CGFloat { phone ? 11 : 20 }
    private var deviceHeight: CGFloat {
        guard let raw else { return 0 }
        return screenW * raw.size.height / raw.size.width + 2 * bezel
    }

    private var deviceView: some View {
        let img = raw!
        let screenH = screenW * img.size.height / img.size.width
        let outerRadius: CGFloat = phone ? 60 : 56
        let innerRadius: CGFloat = phone ? 50 : 38
        return ZStack {
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .fill(Color(hex: 0x0E0D0C))
                .frame(width: screenW + 2 * bezel, height: screenH + 2 * bezel)
                .overlay(
                    RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1.5)
                )
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: screenW, height: screenH)
                .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
        }
        .shadow(color: .black.opacity(0.55), radius: 36, y: 28)
        .rotationEffect(.degrees(spec.tilt))
    }

    private var closing: some View {
        VStack(spacing: phone ? 34 : 56) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: phone ? 180 : 320, height: phone ? 180 : 320)
                    .clipShape(RoundedRectangle(cornerRadius: phone ? 40 : 72, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 20)
            }
            VStack(spacing: phone ? 14 : 22) {
                Text(spec.headline)
                    .font(.system(size: headlineSize, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFAF9F5))
                    .multilineTextAlignment(.center)
                Text(spec.subhead)
                    .font(.system(size: subheadSize))
                    .foregroundStyle(Color(hex: 0xFAF9F5).opacity(0.72))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, sidePad)
        }
    }
}

@MainActor
func renderFrames(rawDir: String, outDir: String, specs: [FrameSpec]) {
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let appIcon = NSImage(contentsOfFile: rawDir + "/appicon.png")
    for spec in specs {
        let raw = spec.image.flatMap { NSImage(contentsOfFile: rawDir + "/" + $0) }
        if spec.image != nil, raw == nil { print("missing", spec.image!); continue }
        NSAppearance.current = NSAppearance(named: .darkAqua)
        let view = StoreFrame(spec: spec, raw: raw, appIcon: appIcon).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = spec.scale
        guard let cg = renderer.cgImage else { print("render failed", spec.name); continue }
        let rep = NSBitmapImageRep(cgImage: cg)
        let data = rep.representation(using: .png, properties: [:])!
        let url = URL(fileURLWithPath: outDir).appendingPathComponent(spec.name + ".png")
        try! data.write(to: url)
        print("wrote \(spec.name) \(cg.width)x\(cg.height)")
    }
}

let phoneSpecs: [FrameSpec] = [
    FrameSpec(name: "iphone-01-all-limits", headline: "All your AI limits,\none glance.", subhead: "Session, weekly and per-model windows for every account you connect, live.", image: "dashboard.png", textOnTop: true, device: .phone),
    FrameSpec(name: "iphone-02-widgets", headline: "Widgets that\nkeep score.", subhead: "Small, medium, large and Lock Screen. One account or all of them.", image: "home-widgets.png", textOnTop: true, device: .phone, tilt: 4),
    FrameSpec(name: "iphone-03-history", headline: "Every reset,\ncharted.", subhead: "24 hours, 7 days or 30 days for each limit, kept on your device.", image: "detail-week30.png", textOnTop: false, device: .phone),
    FrameSpec(name: "iphone-04-alerts", headline: "Alerts before you\nhit the wall.", subhead: "Near-limit, run-out, early-reset and sign-in alerts, per account.", image: "detail-smart.png", textOnTop: true, device: .phone, tilt: 4),
    FrameSpec(name: "iphone-05-pace", headline: "Know your pace.", subhead: "On pace, ahead or behind, and when a window will run out early.", image: "detail-top.png", textOnTop: true, device: .phone, tilt: 4),
    FrameSpec(name: "iphone-06-accounts", headline: "Every account,\nits own icon.", subhead: "Name and icon per account, shown everywhere. Dark mode included.", image: "dashboard-dark.png", textOnTop: true, device: .phone),
    FrameSpec(name: "iphone-07-free", headline: "Free. Open source.\nNo account.", subhead: "No subscription, no server. Nothing leaves your device.", image: nil, textOnTop: true, device: .phone),
]

let padSpecs: [FrameSpec] = [
    FrameSpec(name: "ipad-01-all-limits", headline: "All your AI limits, one glance.", subhead: "Session, weekly and per-model windows for every account you connect, live.", image: "ipad-dashboard.png", textOnTop: true, device: .pad, tilt: -2),
    FrameSpec(name: "ipad-02-history", headline: "Every reset, charted.", subhead: "24 hours, 7 days or 30 days for each limit, kept on your device.", image: "ipad-detail.png", textOnTop: true, device: .pad, tilt: 2),
    FrameSpec(name: "ipad-03-alerts", headline: "Alerts before you hit the wall.", subhead: "Near-limit, run-out, early-reset and sign-in alerts, per account.", image: "ipad-alerts.png", textOnTop: false, device: .pad, tilt: -2),
]
