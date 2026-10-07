import SwiftUI
import UsageKit

/// The glyph that stands in for an account wherever a header reads
/// "icon + name": `ProviderIdentityView` (dashboard, landscape, menu bar,
/// every widget), the Connect sheet header, Privacy & data, and the Live
/// Activity's compact/minimal islands.
///
/// With no `icon` it is an SF Symbol on the app's own accent wash — the
/// default every account starts with, and what shipped alone through
/// 1.5. Since 1.6 the user may pick a glyph per account
/// (`AccountIcon`): any SF Symbol, or one of the two marks in
/// `Media.xcassets` (`ClaudeMark`, `ClaudeCodeMark` — Anthropic's Claude
/// and Claude Code logos as single-path template SVGs, bundled as a
/// deliberate product decision on 2026-10-07 knowing App Review 4.1(c)
/// once flagged brand use in this app; see "App Review posture" in the
/// repo-root CLAUDE.md). Marks are drawn exactly like symbols — a
/// template glyph in the accent on the wash, at the same size — so a
/// header never changes shape or weight with the choice.
struct ProviderMark: View {
    let size: CGFloat
    let cornerRadius: CGFloat
    /// The account's chosen glyph; nil draws the default.
    var icon: AccountIcon? = nil
    /// Filled tile with a white glyph for a sheet-sized header; every inline
    /// header uses the quieter wash + accent glyph the rest of the app's
    /// icon tiles already use (Settings rows, Privacy rows).
    var prominent: Bool = false

    var body: some View {
        Group {
            switch icon {
            case .mark(let mark):
                tile {
                    Image(Self.assetName(for: mark))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.55, height: size * 0.55)
                }
            case .symbol(let name):
                tile {
                    Image(systemName: name)
                        .font(.system(size: size * 0.55, weight: .semibold))
                }
            case nil:
                tile {
                    Image(systemName: Self.defaultSymbol)
                        .font(.system(size: size * 0.55, weight: .semibold))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The glyph every account starts with.
    static let defaultSymbol = "sparkle"

    static func assetName(for mark: AccountIcon.Mark) -> String {
        switch mark {
        case .claude: return "ClaudeMark"
        case .claudeCode: return "ClaudeCodeMark"
        }
    }

    /// The one tile every glyph sits on: accent on the wash, or white on
    /// a filled accent tile when `prominent`.
    private func tile<Glyph: View>(@ViewBuilder _ glyph: () -> Glyph) -> some View {
        glyph()
            .foregroundStyle(prominent ? Color.white : Theme.accent)
            .frame(width: size, height: size)
            .background(
                prominent ? Theme.accent : Theme.accentWash,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}
