#if os(macOS)
import SwiftUI
import UsageKit

/// The expanded island's sessions, under the accounts: a row each (name,
/// folder, what it is doing), a line for the ones past the cap, and while
/// the hooks aren't installed, the one-click invitation to install them.
struct SessionsSection: View {
    let sessions: NotchIslandModel.Sessions
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    private var monitor: ClaudeSessionMonitor { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The demo's captures name no product (the same neutral title
            // as its Claude Code usage section) and offer no hooks.
            Text(model.isDemoMode ? String(localized: "Coding sessions on this Mac") : "Claude Code")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchIslandStyle.reset)
            // With two or more at work, a click on one puts it in the sneak,
            // and the one there is marked.
            let picks = sessions.rotation.count > 1
            ForEach(sessions.rows) { row in
                SessionRowView(
                    row: row,
                    showsPet: sessions.showsPets,
                    isSelected: picks && row.id == sessions.lead?.id,
                    isPickable: picks && row.status != .finished
                )
            }
            if sessions.moreCount > 0 {
                Text("\(sessions.moreCount) more")
                    .font(Theme.caption)
                    .foregroundStyle(NotchIslandStyle.reset)
            }
            if !model.isDemoMode, !monitor.hooksInstalled, !prefs.claudeSessionsHooksDismissed {
                HooksInvitation()
                    .padding(.top, 2)
            }
        }
    }
}

struct SessionRowView: View {
    let row: NotchIslandModel.Sessions.Row
    var showsPet = true
    /// The session the sneak shows.
    var isSelected = false
    /// A click puts it in the sneak (`NotchIslandActions.pickSession`).
    var isPickable = false
    @Environment(\.notchIslandActions) private var actions
    @State private var isHovering = false

    /// The row's pet: a size that sits beside 12 pt text.
    static let petPixel: CGFloat = 1.5

    var body: some View {
        if isPickable, let actions {
            content
                .background { IslandRowHighlight(isSelected: isSelected, isHovering: isHovering) }
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
                .onTapGesture { actions.pickSession(row.id) }
                .accessibilityAddTraits(.isButton)
        } else {
            content
                .background { IslandRowHighlight(isSelected: isSelected, isHovering: false) }
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            if showsPet {
                // The "!" keeps its place on every row, so the names line up.
                HStack(spacing: Self.petPixel) {
                    PixelPetView(pet: row.pet, pose: row.pose, pixel: Self.petPixel)
                    if row.status == .waiting {
                        PixelAlertView(pixel: Self.petPixel)
                    } else {
                        Color.clear.frame(width: 2 * Self.petPixel, height: 1)
                    }
                }
            } else {
                SessionMark(mark: mark)
            }
            HStack(spacing: 6) {
                Text(row.name)
                    .foregroundStyle(.white)
                if let project = row.project {
                    Text(project)
                        .foregroundStyle(NotchIslandStyle.reset)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(row.detail)
                .font(.system(size: 11))
                .foregroundStyle(row.status == .waiting ? Theme.islandWarning : NotchIslandStyle.reset)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var mark: NotchIslandModel.Sessions.Mark {
        switch row.status {
        case .working: .working
        case .waiting: .waiting
        case .finished: .finished
        }
    }
}

/// One line and one click: AIMeter adds itself to Claude Code's hooks
/// (`ClaudeCodeHooks`), which is what lets the island say a session waits
/// for permission. "Not now" puts the offer away for good; Settings ->
/// Claude Code keeps the same button.
struct HooksInvitation: View {
    @Environment(PreferencesModel.self) private var prefs
    private var monitor: ClaudeSessionMonitor { .shared }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let error = monitor.hooksError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.danger)
                    .lineLimit(2)
            } else {
                Text("Install Claude Code hooks to see when a session needs permission.")
                    .foregroundStyle(NotchIslandStyle.reset)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(String(localized: "Not now")) {
                prefs.claudeSessionsHooksDismissed = true
            }
            .foregroundStyle(NotchIslandStyle.reset)
            Button(String(localized: "Install")) {
                monitor.installHooks()
            }
            .foregroundStyle(Theme.accent)
        }
        .font(Theme.caption)
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
