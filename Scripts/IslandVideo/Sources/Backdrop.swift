import AppKit

/// The desktop the island is composed over: a wallpaper in the app's own
/// colors, a menu bar with the frontmost app's menus on the left and a few
/// status icons and the clock on the right, and two terminal windows at
/// work. Drawn, not captured, so a recording shows nothing of the real
/// desktop, and names no other product.
enum Backdrop {
    /// The menu bar's height on a MacBook with a notch.
    static let menuBarHeight: CGFloat = 32
    /// How far the island reaches from the canvas's middle at its widest in
    /// any scene of a language, plus air: the permission peek in both,
    /// measured in the 2026-10-15 take (201 to 758 of 960 pt in English,
    /// 160 to 798 in Spanish, whose session name runs longer). Nothing in
    /// the menu bar is drawn there, so the island never covers a menu or
    /// an icon.
    static func islandReach(language: String) -> CGFloat {
        language == "es" ? 332 : 291
    }

    static func render(size: CGSize, scale: CGFloat, language: String) -> CGImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        // Top-left origin, like the screen's, for AppKit's drawing too.
        let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        drawWallpaper(cg, size: size)
        drawWindows(size: size, language: language)
        drawMenuBar(size: size, language: language)
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    // MARK: Wallpaper

    private static func drawWallpaper(_ cg: CGContext, size: CGSize) {
        let space = CGColorSpaceCreateDeviceRGB()
        let base = CGGradient(colorsSpace: space, colors: [cgColor(0x2B1E19), cgColor(0x120D0B)] as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        for (center, radius, rgb, alpha) in [
            (CGPoint(x: size.width * 0.72, y: size.height * 0.05), size.width * 0.55, 0xD97757, 0.55),
            (CGPoint(x: size.width * 0.12, y: size.height * 0.95), size.width * 0.5, 0x6E4A8C, 0.35),
            (CGPoint(x: size.width * 0.98, y: size.height * 1.0), size.width * 0.45, 0x3C5A8C, 0.3),
        ] {
            let glow = CGGradient(colorsSpace: space, colors: [cgColor(rgb, alpha), cgColor(rgb, 0)] as CFArray, locations: [0, 1])!
            cg.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }
    }

    // MARK: Menu bar

    private static func drawMenuBar(size: CGSize, language: String) {
        NSColor(white: 0, alpha: 0.18).setFill()
        NSRect(x: 0, y: 0, width: size.width, height: menuBarHeight).fill()
        let menus = language == "es"
            ? ["Terminal", "Shell", "Edición", "Visualización", "Ventana", "Ayuda"]
            : ["Terminal", "Shell", "Edit", "View", "Window", "Help"]
        // The island never covers a menu or an icon: whatever would reach
        // into its widest (the canvas's middle, `islandReach` either way) is
        // left out, the way "Avoid covering the menu bar" keeps the real
        // one clear. Help stays last, as on any Mac: the menus before it
        // go first.
        let clearLeft = size.width / 2 - islandReach(language: language)
        let clearRight = size.width / 2 + islandReach(language: language)
        let texts = menus.enumerated().map { index, title in
            NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: index == 0 ? .bold : .regular),
                .foregroundColor: NSColor(white: 1, alpha: 0.92),
            ])
        }
        var shown = texts
        while shown.count > 2, 20 + shown.map({ $0.size().width + 18 }).reduce(0, +) - 18 > clearLeft {
            shown.remove(at: shown.count - 2)
        }
        var x: CGFloat = 20
        for text in shown {
            guard x + text.size().width <= clearLeft else { break }
            text.draw(at: NSPoint(x: x, y: (menuBarHeight - text.size().height) / 2))
            x += text.size().width + 18
        }
        let clock = NSAttributedString(
            string: language == "es" ? "jue 9:41" : "Thu 9:41",
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.92)]
        )
        var right = size.width - 18 - clock.size().width
        clock.draw(at: NSPoint(x: right, y: (menuBarHeight - clock.size().height) / 2))
        for name in ["switch.2", "wifi", "battery.75percent"] {
            let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                .applying(.init(paletteColors: [NSColor(white: 1, alpha: 0.92)]))
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { continue }
            right -= symbol.size.width + 16
            guard right >= clearRight else { break }
            symbol.draw(in: NSRect(x: right, y: (menuBarHeight - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    // MARK: Windows

    /// Two terminals with coding sessions at work, dimmed so the island
    /// leads.
    private static func drawWindows(size: CGSize, language: String) {
        let left = NSRect(x: size.width * 0.07, y: size.height * 0.36, width: size.width * 0.46, height: size.height * 0.5)
        let right = NSRect(x: size.width * 0.5, y: size.height * 0.46, width: size.width * 0.42, height: size.height * 0.44)
        let es = language == "es"
        drawTerminal(right, title: "~/backend", lines: [
            ("›", es ? "Refactorizar el cliente de la API" : "Refactor the API client", 0.85),
            ("●", es ? "Editando src/api/client.ts" : "Editing src/api/client.ts", 0.55),
            ("●", es ? "Corriendo las pruebas" : "Running the tests", 0.55),
        ])
        drawTerminal(left, title: "~/my-app", lines: [
            ("›", es ? "Terminar el onboarding" : "Ship the onboarding", 0.85),
            ("✓", es ? "42 pruebas pasaron" : "42 tests passed", 0.55),
            ("●", es ? "Escribiendo src/onboarding/steps.ts" : "Writing src/onboarding/steps.ts", 0.55),
            ("●", es ? "Revisando los textos" : "Checking the copy", 0.55),
        ])
    }

    private static func drawTerminal(_ frame: NSRect, title: String, lines: [(String, String, CGFloat)]) {
        let shape = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        NSColor(calibratedRed: 0.11, green: 0.09, blue: 0.08, alpha: 0.92).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 1, alpha: 0.08).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        for (index, rgb) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            nsColor(rgb, 0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: frame.minX + 14 + CGFloat(index) * 18, y: frame.minY + 12, width: 11, height: 11)).fill()
        }
        let titleText = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.45),
        ])
        titleText.draw(at: NSPoint(x: frame.midX - titleText.size().width / 2, y: frame.minY + 10))
        var y = frame.minY + 46
        for (mark, text, alpha) in lines {
            let line = NSMutableAttributedString(string: "\(mark)  ", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: nsColor(0xE08B6D, alpha),
            ])
            line.append(NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor(white: 1, alpha: alpha),
            ]))
            line.draw(at: NSPoint(x: frame.minX + 20, y: y))
            y += 24
        }
    }

    private static func nsColor(_ rgb: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha
        )
    }

    private static func cgColor(_ rgb: Int, _ alpha: CGFloat = 1) -> CGColor {
        nsColor(rgb, alpha).cgColor
    }
}
