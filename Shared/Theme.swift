import SwiftUI

/// AIMeter design tokens — single source of truth for app and widgets.
///
/// Identity: warm, editorial, Claude-inspired. Terracotta accent over warm
/// ivory/charcoal neutrals, a serif display face for headers (nod to
/// Claude's editorial serif), sans body, monospaced digits for numbers.
/// Deliberately distinct from stock-iOS blue/gray utility apps.
enum Theme {
    // MARK: - Palette (all colors adapt to light/dark)

    /// Terracotta — bars, buttons, links, selected states. (#D97757)
    static let accent = Color(light: 0xD97757, dark: 0xE08B6D)
    /// Soft accent wash for pills, selected segments, icon chips.
    static let accentWash = Color(light: 0xD97757, dark: 0xE08B6D).opacity(0.14)
    /// Burnt red for windows ≥ 90% used or provider-flagged critical.
    static let danger = Color(light: 0xB3261E, dark: 0xE5695E)

    /// Screen background: warm ivory / warm charcoal.
    static let background = Color(light: 0xFAF9F5, dark: 0x262624)
    /// Card surface.
    static let card = Color(light: 0xFFFFFF, dark: 0x30302E)
    /// Progress bar track and hairlines: warm paper.
    static let track = Color(light: 0xEDEAE1, dark: 0x3E3D3A)

    /// Primary text: warm near-black / warm ivory.
    static let ink = Color(light: 0x1F1E1D, dark: 0xFAF9F5)
    /// Secondary text (reset lines, footers, captions).
    static let inkSecondary = Color(light: 0x87867F, dark: 0x9B9A93)

    // MARK: - Typography

    /// Section headers ("Claude", "Display", "Rate limits").
    static let sectionHeader = Font.subheadline.weight(.medium)
    /// Window name in a usage row ("5-hour session").
    static let rowTitle = Font.body.weight(.medium)
    /// Percentage next to a bar — always monospaced digits.
    static let percent = Font.body.monospacedDigit().weight(.semibold)
    /// Reset line, "Updated X ago", footnotes.
    static let caption = Font.footnote

    // MARK: - Elevation

    /// Wide, diffuse drop shadow under cards — the soft "glass float"
    /// elevation. Pair with `shadowTight` for a grounded edge.
    static let shadowSoft = Color.black.opacity(0.07)
    /// Tight contact shadow that grounds the card edge.
    static let shadowTight = Color.black.opacity(0.04)

    // MARK: - Metrics

    /// Card corner radius (continuous).
    static let cardRadius: CGFloat = 20
    /// Inner padding of cards.
    static let cardPadding: CGFloat = 16
    /// Progress bar height (capsule).
    static let barHeight: CGFloat = 6
    /// Vertical gap between sections.
    static let sectionSpacing: CGFloat = 24
    /// Vertical gap between rows inside a card.
    static let rowSpacing: CGFloat = 14
}

extension Color {
    /// Dynamic color from light/dark hex values (0xRRGGBB).
    init(light: UInt32, dark: UInt32) {
        #if os(macOS)
        self.init(NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(Color(hex: hex))
        })
        #else
        self.init(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #endif
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
