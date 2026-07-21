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
                header
                if model.needsConnection {
                    Text("Sign in to see your usage.")
                        .font(.callout)
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    Card {
                        WindowRowsList(snapshot: model.snapshot)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .statusBarHidden()
    }

    private var header: some View {
        HStack(spacing: 8) {
            ProviderIdentityView(
                name: "Claude",
                iconSize: 22,
                iconCornerRadius: 6,
                font: Theme.sectionHeader,
                nameColor: Theme.inkSecondary,
                planName: model.snapshot?.planName
            )
            Spacer()
            if let snapshot = model.snapshot {
                Text(UsageFormatting.updatedLabel(snapshot.fetchedAt))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}
#endif
