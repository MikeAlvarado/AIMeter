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
            Image("ClaudeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("Claude")
                .font(Theme.sectionHeader)
                .foregroundStyle(Theme.inkSecondary)
            if let plan = model.snapshot?.planName {
                Text(plan.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Theme.track.opacity(0.7), in: Capsule())
            }
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
