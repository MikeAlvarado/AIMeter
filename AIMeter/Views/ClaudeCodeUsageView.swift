#if os(macOS)
import SwiftUI
import UsageKit

/// The Claude Code usage detail: one bucket at a time (Today / This week /
/// This month / All time), its token breakdown and equivalent cost, then
/// the same per model. The footnote is the honesty line — list prices as
/// of `ClaudeModelPricing.lastVerified`, "not a bill", which folder was
/// read — and, when Claude Code's own totals exist for the same
/// sessions, how far the table is from them.
struct ClaudeCodeUsageView: View {
    @Environment(UsageModel.self) private var model
    @State private var bucket: ClaudeCodeUsageModel.Bucket = .today

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let usage = model.claudeCode {
                    SegmentedPill(options: ClaudeCodeUsageModel.Bucket.allCases.map { ($0, $0.label) }, selection: $bucket)
                    let aggregate = usage.aggregate(bucket)

                    SectionHeader(title: String(localized: "Usage"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    if aggregate.messages == 0 {
                        Card {
                            Label(usage.isScanning ? String(localized: "Scanning…") : String(localized: "No messages in this period."), systemImage: usage.isScanning ? "magnifyingglass" : "tray")
                                .font(Theme.rowTitle)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    } else {
                        DetailRowsCard(rows: rows(aggregate))
                        SectionHeader(title: String(localized: "By model"))
                            .padding(.top, Theme.sectionSpacing - 10)
                        DetailRowsCard(rows: aggregate.byModel.map { entry in (entry.model, modelValue(entry)) })
                    }

                    Button {
                        usage.rescan()
                    } label: {
                        Label(String(localized: "Rescan"), systemImage: "arrow.clockwise")
                            .font(Theme.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(usage.isScanning)
                    .padding(.top, 4)

                    SectionFootnote(text: footnote(usage))
                        .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle(Text("Claude Code on this Mac"))
    }

    private func rows(_ aggregate: ClaudeCodeUsageAggregate) -> [(String, String)] {
        let t = aggregate.tokens
        var rows: [(String, String)] = [
            (String(localized: "Equivalent API cost"), aggregate.cost.map { (aggregate.hasUnpricedModels ? "> " : "≈ ") + UsageFormatting.usd($0) } ?? "—"),
            (String(localized: "Tokens"), UsageFormatting.tokens(t.total)),
            (String(localized: "Input"), UsageFormatting.tokens(t.input)),
            (String(localized: "Output (incl. thinking)"), UsageFormatting.tokens(t.output)),
            (String(localized: "Cache writes"), UsageFormatting.tokens(t.cacheWrite5m + t.cacheWrite1h)),
            (String(localized: "Cache reads"), UsageFormatting.tokens(t.cacheRead)),
        ]
        if t.webSearches > 0 {
            rows.append((String(localized: "Web searches"), "\(t.webSearches)"))
        }
        rows.append((String(localized: "Messages"), "\(aggregate.messages)"))
        rows.append((String(localized: "Sessions"), "\(aggregate.sessions)"))
        return rows
    }

    private func modelValue(_ entry: ClaudeCodeUsageAggregate.ModelUsage) -> String {
        let tokens = UsageFormatting.tokens(entry.tokens.total)
        guard let cost = entry.cost else { return "\(tokens) · —" }
        return "\(tokens) · ≈ \(UsageFormatting.usd(cost))"
    }

    private func footnote(_ usage: ClaudeCodeUsageModel) -> String {
        let verified = ClaudeModelPricing.lastVerified.formatted(date: .abbreviated, time: .omitted)
        let path = usage.root.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        var text = String(localized: "Equivalent cost at Anthropic's list prices as of \(verified). Your subscription already covers this usage — it is not a bill. Read from \(path).")
        if let drift = usage.pricingDrift, drift.theirs > 0 {
            let apart = abs(drift.ours - drift.theirs) / drift.theirs
            let percent = apart.formatted(.percent.precision(.fractionLength(0)))
            text += " " + String(localized: "Claude Code's own totals for the same sessions come to \(UsageFormatting.usd(drift.theirs)) (\(percent) apart).")
        }
        return text
    }
}
#endif
