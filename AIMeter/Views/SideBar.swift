#if os(iOS)
import SwiftUI

// iPhone Duo's side bar. In some poses (always on the outer display,
// closed) the system lays a screen's navigation bar and toolbar
// vertically beside the status bar, and takes only the system's own
// toolbar items there, each with an icon: a view of the app's never goes,
// and an item with a title and no icon keeps the whole bar horizontal.
// Everywhere else, every other iPhone included, nothing here changes what
// shows.

/// The Dashboard's buttons: while the bar is vertical, Settings and
/// Refresh leave the drawn header (`RoundIconButton`) for the system
/// toolbar; otherwise the navigation bar stays hidden and the header is
/// the Dashboard's, as always.
struct DashboardSideBar: ViewModifier {
    @Binding var isVertical: Bool
    let isRefreshing: Bool
    let settings: () -> Void
    let refresh: () -> Void

    func body(content: Content) -> some View {
        content
            .readsVerticalBar($isVertical)
            .toolbar {
                if isVertical {
                    // The top of the bar is for navigation, then the
                    // prominent action (Apple's order): Settings leads,
                    // Refresh follows.
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: settings) {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: refresh) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(isRefreshing)
                    }
                }
            }
            .toolbar(isVertical ? .visible : .hidden, for: .navigationBar)
    }
}

/// A sheet's Done: the word, as before, and a checkmark on the side bar,
/// which a title alone would have kept horizontal (measured on the iPhone
/// Duo simulator: Settings' Done stayed at the top while every other bar
/// of the app went to the side).
struct SheetDoneButton: View {
    let action: () -> Void
    @State private var isVertical = false

    var body: some View {
        Button(action: action) {
            if isVertical {
                Label("Done", systemImage: "checkmark")
            } else {
                Text("Done")
            }
        }
        .readsVerticalBar($isVertical)
    }
}

extension View {
    /// Keeps `isVertical` on whether the system presents this screen's
    /// bars vertically (`toolbarVerticalEdge`, iOS 27.1; never before).
    /// Reported even while the navigation bar is hidden, which is what
    /// lets the Dashboard decide.
    func readsVerticalBar(_ isVertical: Binding<Bool>) -> some View {
        modifier(VerticalBarReader(isVertical: isVertical))
    }
}

private struct VerticalBarReader: ViewModifier {
    @Binding var isVertical: Bool

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.modifier(EdgeReader(isVertical: $isVertical))
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
private struct EdgeReader: ViewModifier {
    @Binding var isVertical: Bool
    @Environment(\.toolbarVerticalEdge) private var edge

    func body(content: Content) -> some View {
        content
            .onAppear { isVertical = edge != nil }
            .onChange(of: edge) { _, edge in isVertical = edge != nil }
    }
}
#endif
