import SwiftUI
import UsageKit

/// Where each Dashboard account section sits, keyed by accountID and
/// resolved in the Dashboard's own named coordinate space.
///
/// The reorder gesture needs this because it isn't a drag *session*: there
/// is no system drop target to ask "is the finger over you". The gesture
/// gets a location, and these rects are what turn that location into "the
/// card it would land on". Sections never overlap, so a plain merge is
/// enough — every section publishes only its own entry.
struct AccountSectionFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Outlines the section a release would drop onto. The only feedback the
/// reorder gives besides the card following the finger, since it resolves
/// on release rather than live — so it has to be unambiguous about which
/// slot the card is about to take.
struct AccountDropHighlight: View {
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(Theme.accent, lineWidth: 2)
            .opacity(isTargeted ? 1 : 0)
            .allowsHitTesting(false)
    }
}
