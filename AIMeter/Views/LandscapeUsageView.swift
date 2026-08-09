#if os(iOS)
import SwiftUI
import UsageKit

/// Fullscreen landscape mode: rotating the phone shows the same stacked
/// usage rows as the dashboard — full-width bars, one after another, with
/// the shared reset-grouping rule. Rotating back returns to the regular
/// dashboard (see ContentView).
struct LandscapeUsageView: View {
    @Environment(UsageModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if model.needsConnection {
                    Text("Sign in to see your usage.")
                        .font(.callout)
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    // No ancestor NavigationStack here (ContentView renders
                    // this view outside one), so links to Provider Detail
                    // aren't available — same reasoning the menu bar popover
                    // already documents for its own `linksToDetail: false`.
                    ForEach(model.accounts) { usage in
                        AccountSectionView(usage: usage, linksToDetail: false)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .statusBarHidden()
    }
}
#endif
