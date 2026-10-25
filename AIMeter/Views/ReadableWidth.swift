import SwiftUI

extension View {
    /// A page of rows on an iPad reads at a column's width, centred, rather
    /// than stretched across the screen: account detail, an account's
    /// settings, Settings. Nothing changes on an iPhone or a Mac.
    func readableWidth() -> some View {
        modifier(ReadableWidth())
    }
}

private struct ReadableWidth: ViewModifier {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// About the width of a Settings form on iPad.
    static let maxWidth: CGFloat = 680

    func body(content: Content) -> some View {
        #if os(iOS)
        if sizeClass == .regular {
            content
                .frame(maxWidth: Self.maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
