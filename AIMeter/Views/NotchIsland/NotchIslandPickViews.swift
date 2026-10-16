#if os(macOS)
import SwiftUI

/// Behind a row of the open island that a click puts in the sneak: a soft
/// panel on the one there now, a fainter one under the cursor. Drawn past
/// the row's own frame, so nothing around it moves.
struct IslandRowHighlight: View {
    let isSelected: Bool
    let isHovering: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white.opacity(isSelected ? 0.08 : isHovering ? 0.05 : 0))
            .padding(.horizontal, -8)
            .padding(.vertical, -4)
            .animation(.easeOut(duration: 0.12), value: isSelected)
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// A click on any part of an account in the open island puts its figures
/// in the sneak (`NotchIslandActions.pickAccount`).
struct PicksAccount: ViewModifier {
    let id: String
    let enabled: Bool
    @Environment(\.notchIslandActions) private var actions

    func body(content: Content) -> some View {
        if enabled, let actions {
            content
                .contentShape(Rectangle())
                .onTapGesture { actions.pickAccount(id) }
        } else {
            content
        }
    }
}

extension View {
    func picksAccount(_ id: String, if enabled: Bool) -> some View {
        modifier(PicksAccount(id: id, enabled: enabled))
    }
}
#endif
