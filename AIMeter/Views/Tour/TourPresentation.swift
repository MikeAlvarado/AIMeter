import SwiftUI

#if os(macOS)
/// The tour in its own window (`AIMeterApp.tourWindowID`), at the first
/// launch and from Settings. Closing the window counts as skipping it;
/// asking to connect opens the Connect sheet on the Dashboard once the
/// window is gone.
struct TourWindow: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        // One height for every step (more only where a language needs it),
        // so the buttons never move under the pointer. The tour itself
        // reaches up under the hidden title bar, "Skip tour" level with the
        // window's buttons: ignoring the safe area there, inside the frame,
        // grows the tour into it, while the window is sized from the frame.
        TourView(topPadding: 12) { connect in
            Tour.finish()
            dismissWindow(id: AIMeterApp.tourWindowID)
            if connect {
                AppChrome.connect(.add)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(width: 460)
        .frame(minHeight: 530)
        .fixedSize(horizontal: false, vertical: true)
        .appBackground()
        .background(NonRestorableWindow())
        .onDisappear(perform: Tour.finish)
    }
}

/// Keeps its window out of state restoration. A relaunch that restored only
/// such a window (the tour, the update notice) would open no Dashboard, the
/// scene whose first appearance hands AppKit its way to open windows
/// (`AppChrome`): with them left out, the launch opens the Dashboard as
/// always (and the delegate closes it), and whatever is still due opens
/// again on its own.
struct NonRestorableWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowHook() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowHook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isRestorable = false
        }
    }
}
#else
/// The tour over the whole screen, at the first launch and from Settings:
/// the step at the top and its buttons at the bottom, scrolling only where
/// a large text size makes it taller than the screen.
struct TourCover: View {
    let finish: (_ connect: Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                TourView(finish: finish)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .appBackground()
    }
}
#endif

/// Settings' "Show the tour": the full tour again, whatever was turned on
/// since. On iOS it opens once the Settings sheet is gone
/// (`Tour.deliverPendingShow`).
struct TourSettings: View {
    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        Card {
            Button {
                #if os(macOS)
                AppChrome.openTourWindow()
                #else
                Tour.showRequested = true
                dismiss()
                #endif
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Show the tour")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        SectionFootnote(text: String(localized: "What each part of AIMeter does, one at a time, with a button to turn it on."))
    }
}
