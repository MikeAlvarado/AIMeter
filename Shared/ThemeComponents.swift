import SwiftUI
import UsageKit

/// Thin capsule progress bar — the same bar in app and widgets.
struct UsageBarView: View {
    /// 0–100; nil renders an empty track (missing window slot).
    let value: Double?
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                if let value {
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(max(value, 0), 100) / 100)
                }
            }
        }
        .frame(height: Theme.barHeight)
        // Decorative: the row already exposes the name and percentage.
        .accessibilityHidden(true)
    }
}

/// Two/three-option pill selector matching the visual identity (used for
/// Remaining/Used, Relative/Absolute, System/Light/Dark).
struct SegmentedPill<Option: Hashable>: View {
    let options: [(value: Option, label: String)]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(selection == option.value ? .semibold : .regular))
                        .foregroundStyle(selection == option.value ? Theme.ink : Theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selection == option.value {
                                Capsule().fill(Theme.accentWash)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.track.opacity(0.6), in: Capsule())
    }
}

/// Card container with the standard surface, radius, and padding.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.card,
                in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            )
            .shadow(color: Theme.shadowSoft, radius: 16, x: 0, y: 8)
            .shadow(color: Theme.shadowTight, radius: 2, x: 0, y: 1)
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

/// Error label (if the last fetch failed) and "Updated X ago" caption (if
/// there's a snapshot) — the shared tail of the rate-limit rows on the
/// dashboard, provider detail, and the menu bar popover. The dashboard and
/// provider detail cards precede each with a hairline divider;
/// `showsDividers: false` skips those for the menu bar popover, which
/// already has its own dividers bracketing this whole section.
struct UsageStatusFooter: View {
    let snapshot: UsageSnapshot?
    let error: String?
    var showsDividers = true

    var body: some View {
        if let error {
            if showsDividers { Divider().overlay(Theme.track) }
            Label(error, systemImage: "exclamationmark.triangle")
                .font(Theme.caption)
                .foregroundStyle(Theme.danger)
        }
        if let snapshot {
            if showsDividers { Divider().overlay(Theme.track) }
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
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Theme.accent, in: Capsule())
    }
}
