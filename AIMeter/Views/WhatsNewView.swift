import SwiftUI

/// A release's notes: a header, one row per item (its symbol on the accent
/// wash, a title and a line or two of detail) and the caller's buttons.
/// The iOS sheet after an update and the Mac's update notice both draw it.
struct WhatsNewView<Actions: View>: View {
    let release: WhatsNew.Release
    /// "What's new in AIMeter 2.1.0" unless the caller says otherwise (the
    /// Mac's notice: "AIMeter 2.1.0 is ready").
    var title: String? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                Text(title ?? String(localized: "What's new in AIMeter \(release.version)"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 18) {
                ForEach(release.items) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 38, height: 38)
                            .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(WhatsNew.text(item.title, language: WhatsNew.appLanguage))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(WhatsNew.text(item.detail, language: WhatsNew.appLanguage))
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            actions
        }
    }
}

/// The notes' buttons: filled in the accent for the main action, on the
/// accent wash for the other. The label claims the whole capsule, which
/// is drawn outside it (see "Hit areas" in the repo-root CLAUDE.md).
struct CapsuleActionButton: View {
    let title: String
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.white : Theme.accent)
        .background(prominent ? Theme.accent : Theme.accentWash, in: Capsule())
    }
}

#if os(iOS)
/// The notes as an iOS sheet as tall as they are, not a full-screen card
/// with most of it empty: the content is measured and the sheet's one
/// detent is that height plus the home indicator's inset. Notes taller
/// than the screen get the full height and scroll.
struct WhatsNewSheet: View {
    let release: WhatsNew.Release
    let dismiss: () -> Void
    @State private var contentHeight: CGFloat = 0
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        ScrollView {
            WhatsNewView(release: release) {
                CapsuleActionButton(title: String(localized: "Continue"), action: dismiss)
            }
            .padding(24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .background(Theme.background)
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight + bottomInset)] : [.large])
    }
}
#endif
