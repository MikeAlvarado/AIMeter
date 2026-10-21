import SwiftUI

/// A release's notes: a header, one row per item (its symbol on the accent
/// wash, a title and a line or two of detail) and the caller's buttons.
/// An item that names a tour feature carries that feature's card under it
/// (`TourFeatureCard`: its animation, and the button that turns it on).
/// The iOS sheet after an update and the Mac's update window both draw it.
struct WhatsNewView<Actions: View>: View {
    let release: WhatsNew.Release
    /// "What's new in AIMeter 2.1.0" unless the caller says otherwise (the
    /// Mac's notice: "AIMeter 2.1.0 is ready").
    var title: String? = nil
    /// Off in the Mac's notice before an update installs: the running
    /// version can't turn on what only the next one has. Its cards come
    /// after the restart instead (`Tour.pendingOffers`).
    var showsFeatures = true
    @ViewBuilder var actions: Actions
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    /// The features whose cards show, decided once as the notes open: the
    /// ones that apply here and are still off, or only explain (the
    /// colors). Decided once, so a card turned on from here stays to say
    /// "On" instead of vanishing under the user's click.
    @State private var cards: Set<TourFeature> = []

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
                    VStack(alignment: .leading, spacing: 12) {
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
                        if let feature = item.tourFeature, cards.contains(feature) {
                            // Under the text, past the symbol's column.
                            TourFeatureCard(feature: feature)
                                .padding(.leading, 52)
                        }
                    }
                }
            }
            actions
        }
        .onAppear {
            guard showsFeatures else { return }
            #if os(macOS)
            // Whether the hooks are in is read from Claude Code's settings,
            // and may not have been yet at launch.
            ClaudeSessionMonitor.shared.refreshHooksState()
            #endif
            // Notifications' state is only known asynchronously; read as
            // off here, an alerts card shows, and its own check turns its
            // button into "On" if they are allowed already.
            cards = Set(release.items.compactMap(\.tourFeature).filter { feature in
                TourActions.applies(feature, prefs: prefs)
                    && (!feature.canBeTurnedOn || !TourActions.isActive(feature, model: model, prefs: prefs, notificationsAllowed: false))
            })
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
        .appBackground()
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight + bottomInset)] : [.large])
    }
}
#endif
