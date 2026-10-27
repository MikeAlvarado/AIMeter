import SwiftUI
import UsageKit

/// Thin capsule progress bar — the same bar in app and widgets.
struct UsageBarView: View {
    /// 0–100; nil renders an empty track (missing window slot).
    let value: Double?
    let tint: Color
    var height: CGFloat = Theme.barHeight
    /// The protagonist's bar on an account card: its fill easing into its
    /// full color from the leading end. Quiet on purpose: no glow, nothing
    /// that shines (Mike, 2026-10-21).
    var lit = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                if let value {
                    Capsule()
                        .fill(lit
                              ? AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .leading, endPoint: .trailing))
                              : AnyShapeStyle(tint))
                        .frame(width: proxy.size.width * min(max(value, 0), 100) / 100)
                }
            }
        }
        .frame(height: height)
        // Decorative: the row already exposes the name and percentage.
        .accessibilityHidden(true)
    }
}

/// Two/three-option pill selector matching the visual identity (used for
/// Remaining/Used, Relative/Absolute, System/Light/Dark).
struct SegmentedPill<Option: Hashable>: View {
    let options: [(value: Option, label: String)]
    @Binding var selection: Option
    /// What the choice is, said by VoiceOver before the segments ("Display,
    /// Used, selected"): usually the section's own header.
    var name: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                Button {
                    if reduceMotion {
                        selection = option.value
                    } else {
                        withAnimation(.snappy(duration: 0.18)) {
                            selection = option.value
                        }
                    }
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(selection == option.value ? .semibold : .regular))
                        .foregroundStyle(selection == option.value ? Theme.ink : Theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        // 44 pt a segment on iOS, the size a finger needs
                        // (36 until 4.3.1); the Mac's pointer keeps 8.
                        .padding(.vertical, Self.segmentPadding)
                        .background {
                            if selection == option.value {
                                Capsule().fill(Theme.accentWash)
                            }
                        }
                        // An unselected segment draws no background, so
                        // without this only its word would be tappable and
                        // a tap beside the word would do nothing.
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.track.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name.map { Text($0) } ?? Text(verbatim: ""))
    }

    #if os(iOS)
    private static var segmentPadding: CGFloat { 12 }
    #else
    private static var segmentPadding: CGFloat { 8 }
    #endif
}

/// Card container with the standard surface, radius, and padding. It
/// stacks what it is given itself, rows apart: modifiers on a bare list
/// of views reach each view on its own, so a card handed its rows without
/// a stack drew one card per row (Provider Detail's Account card showed
/// Name, its divider and Icon as three, from 1.6 to 3.0.1).
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            content
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// Section header text above a card.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.sectionHeader)
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 4)
            // VoiceOver's Headings rotor moves between sections.
            .accessibilityAddTraits(.isHeader)
    }
}

/// Footnote text below a card.
struct SectionFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 4)
    }
}

/// Error label (if the last fetch failed) and "Updated X ago" caption — the
/// shared tail of an account's rows on the dashboard card, provider detail,
/// and the menu bar popover. No hairlines: spacing alone sets it apart, as
/// it does every row since 4.0.
struct UsageStatusFooter: View {
    let snapshot: UsageSnapshot?
    let error: String?
    /// Supplied only when the failure was a credential one
    /// (`UsageModel.AccountUsage.needsReauthentication`) — it replaces the
    /// raw endpoint message with an actionable prompt. The raw text is
    /// deliberately dropped in that one case: "The provider rejected the
    /// credentials" describes the HTTP exchange faithfully and tells the
    /// user nothing they can act on, which is the opposite of the point of
    /// carrying raw bodies for every *other* error.
    var reauthenticate: (() -> Void)?
    /// The error is a lost network, not a provider failure
    /// (`UsageModel.AccountUsage.isOffline`): rendered quietly in the
    /// secondary color, since the last snapshot is still valid and there
    /// is nothing for the user to fix.
    var offline = false
    /// Set when the provider itself reports an incident while this
    /// account's refresh is failing (`UsageModel.incidentNote(for:)`): one
    /// quiet line under the raw error saying so. The raw body stays — the
    /// typed-errors rule — this only adds the context that makes it
    /// readable as "their outage", not "your account".
    var serviceIncident: String?
    /// "Updated X ago": `.always` on Provider Detail; `.whenStale` on the
    /// Dashboard's cards and in the popover, whose own header says when the
    /// accounts last refreshed, so a card only speaks up once its figures
    /// fall behind (`UsageSnapshot.isStale`).
    var updated: UpdatedLine = .always

    enum UpdatedLine {
        case always, whenStale
    }

    var body: some View {
        if let reauthenticate {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(String(localized: "Sign-in expired. Usage can't refresh."), systemImage: "exclamationmark.triangle")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                Spacer(minLength: 0)
                Button(String(localized: "Sign in again"), action: reauthenticate)
                    .buttonStyle(.plain)
                    .font(Theme.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .tapTarget()
            }
        } else if let error {
            Label(error, systemImage: offline ? "wifi.slash" : "exclamationmark.triangle")
                .font(Theme.caption)
                .foregroundStyle(offline ? Theme.inkSecondary : Theme.danger)
            if let serviceIncident {
                Label(serviceIncident, systemImage: "exclamationmark.icloud")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        if let snapshot, updated == .always || snapshot.isStale {
            Text(UsageFormatting.updatedLabel(snapshot.fetchedAt))
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

/// "Sign in to see your usage" text + Connect button, shown when a
/// provider has no stored credentials yet. Holds only the content that's
/// identical everywhere — callers still wrap it in their own container
/// for whatever alignment/spacing their surface needs (a centered card on
/// the dashboard, a left-aligned list in the menu bar popover), same as
/// `ProviderIdentityView`.
struct DisconnectedPrompt: View {
    let buttonLabel: LocalizedStringKey
    var verticalPadding: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Text("Sign in to see your usage.")
            .font(.callout)
            .foregroundStyle(Theme.inkSecondary)
        Button(action: action) {
            Label(buttonLabel, systemImage: "link")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                // The capsule below is outside the button, so the label has
                // to claim the whole shape itself or only the text would
                // respond to a tap (a `.plain` button hit-tests its label,
                // and a transparent frame isn't opaque content).
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Theme.accent, in: Capsule())
    }
}

extension View {
    /// A finger's 44 pt of height around a small text control (a link-like
    /// button, a reset line), without moving anything: the padding that
    /// widens the hit area is taken back from the layout.
    func tapTarget() -> some View {
        #if os(iOS)
        let extra: CGFloat = 12
        return padding(.vertical, extra)
            .contentShape(Rectangle())
            .padding(.vertical, -extra)
        #else
        return self
        #endif
    }
}
