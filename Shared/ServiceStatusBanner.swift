import SwiftUI
import UsageKit

/// The "the provider is having an incident" notice, composed once for the
/// two surfaces that show it (dashboard, macOS menu bar popover). Rendered
/// only while `ServiceStatus.isDegraded`; the caller decides that. Tapping
/// opens the incident's own page, or the status page when the incident
/// has no link of its own. Tint follows severity with the app's two
/// colors: `Theme.danger` for a major or critical outage, the accent for
/// anything milder — never a third color.
struct ServiceStatusBanner: View {
    let providerName: String
    let status: ServiceStatus
    var fallbackURL: URL?
    /// Tighter padding and radius for the popover.
    var compact = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = status.incidentURL ?? fallbackURL {
                openURL(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(providerName): \(status.description)")
                        .font(compact ? Theme.sectionHeader : Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(compact ? 10 : Theme.cardPadding)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: compact ? 12 : Theme.cardRadius, style: .continuous))
            // The background is drawn outside the label, so the label has
            // to claim the whole shape or only the text would respond.
            .contentShape(RoundedRectangle(cornerRadius: compact ? 12 : Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }

    private var tint: Color {
        switch status.indicator {
        case .major, .critical: Theme.danger
        case .minor, .maintenance, .operational, .unknown: Theme.accent
        }
    }

    private var detail: String {
        if let title = status.incidentTitle { return title }
        if !status.affectedComponents.isEmpty {
            return String(localized: "Affected: \(status.affectedComponents.joined(separator: ", "))")
        }
        return String(localized: "See the status page")
    }
}
