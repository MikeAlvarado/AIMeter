#if os(macOS)
import SwiftUI
import UsageKit

/// Push target for the Claude Code detail screen (`DashboardView`'s
/// `navigationDestination`).
enum ClaudeCodeUsageRoute: Hashable {
    case detail
}

/// Dashboard → "Claude Code on this Mac": the invitation while the
/// feature is off (only if Claude Code has logs here, and until
/// dismissed), the three-bucket summary once it's on. Hidden in demo mode
/// — there is nothing neutral to fabricate for it, and screenshots
/// shouldn't carry a third-party product name.
struct ClaudeCodeSection: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        if let usage = model.claudeCode, !model.isDemoMode {
            if usage.enabled {
                SectionHeader(title: String(localized: "Claude Code on this Mac"))
                ClaudeCodeSummaryCard(usage: usage)
            } else if !prefs.claudeCodeUsageDismissed, usage.logsExist {
                SectionHeader(title: String(localized: "Claude Code on this Mac"))
                ClaudeCodeInviteCard()
            }
        }
    }
}

private struct ClaudeCodeInviteCard: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("See what your Claude Code sessions on this Mac would cost at API prices. AIMeter reads only the token counts from its local logs — never what you wrote or what it answered.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button {
                        prefs.claudeCodeUsageEnabled = true
                        model.claudeCode?.setEnabled(true)
                    } label: {
                        Text("Enable")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Theme.accent, in: Capsule())

                    Button {
                        prefs.claudeCodeUsageDismissed = true
                    } label: {
                        Text("Not now")
                            .font(.body)
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ClaudeCodeSummaryCard: View {
    let usage: ClaudeCodeUsageModel

    var body: some View {
        NavigationLink(value: ClaudeCodeUsageRoute.detail) {
            Card {
                VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                    ForEach(Array([ClaudeCodeUsageModel.Bucket.today, .week, .month].enumerated()), id: \.offset) { index, bucket in
                        if index > 0 { Divider().overlay(Theme.track) }
                        let aggregate = usage.aggregate(bucket)
                        HStack(alignment: .firstTextBaseline) {
                            Text(bucket.label)
                                .font(Theme.rowTitle)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(ClaudeCodeFormatting.summary(aggregate))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    if usage.isScanning, usage.ledger.entries.isEmpty {
                        Divider().overlay(Theme.track)
                        Label(String(localized: "Scanning…"), systemImage: "magnifyingglass")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    HStack {
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

enum ClaudeCodeFormatting {
    /// "1.2M tokens · ≈ $4.10", or "—" for an empty bucket.
    static func summary(_ aggregate: ClaudeCodeUsageAggregate) -> String {
        guard aggregate.messages > 0 else { return "—" }
        let tokens = String(localized: "\(UsageFormatting.tokens(aggregate.tokens.total)) tokens")
        guard let cost = aggregate.cost else { return tokens }
        let prefix = aggregate.hasUnpricedModels ? "> " : "≈ "
        return "\(tokens) · \(prefix)\(UsageFormatting.usd(cost))"
    }
}
#endif
