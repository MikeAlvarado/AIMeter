#if os(macOS)
import SwiftUI
import UsageKit

/// The expanded island's sessions, under the accounts: a row each (name,
/// folder, what it is doing), a line for the ones past the cap, and while
/// the hooks aren't installed, the one-click invitation to install them.
struct SessionsSection: View {
    let sessions: NotchIslandModel.Sessions
    /// The session whose card shows, fixed while the island is open: the
    /// sneak's lead when it opened, then whichever row the user clicks. The
    /// lead changes on its own as turns start and end, and a card that
    /// changed under the pointer took a Stop meant for another session.
    @State private var pinned: String?
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
            // The session in the sneak opens up into its card, its steps
            // and what can be done about it; the others stay rows.
            let cardID = NotchIslandModel.Sessions.cardID(rows: sessions.rows, lead: sessions.lead?.id, pinned: pinned)
            let card = sessions.rows.first { $0.id == cardID }
            if let card, let turn = card.turn {
                // One card in its place: the session leaving fades out
                // before the one clicked in fades in, the two never drawn
                // over each other, and the new one's edge flashes.
                ZStack {
                    SessionCard(row: card, turn: turn, showsPet: sessions.showsPets)
                        .id(card.id)
                        .transition(.notchSwap)
                }
                .animation(.smooth(duration: 0.3), value: card.id)
                .padding(.bottom, 4)
            }
            ForEach(sessions.rows.filter { $0.id != card?.id }) { row in
                SessionRowView(
                    row: row,
                    showsPet: sessions.showsPets,
                    isSelected: picks && card == nil && row.id == sessions.lead?.id,
                    isPickable: picks && row.status != .finished,
                    onPick: { pinned = row.id }
                )
                // A row trading places with the card swaps at once: faded,
                // the two names showed over each other for a moment.
                .transaction { $0.animation = nil }
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
        .onAppear { pinned = NotchIslandModel.Sessions.cardID(rows: sessions.rows, lead: sessions.lead?.id, pinned: nil) }
        .onChange(of: cardID) { _, id in if id != nil, pinned != id { pinned = id } }
    }

    private var cardID: String? {
        NotchIslandModel.Sessions.cardID(rows: sessions.rows, lead: sessions.lead?.id, pinned: pinned)
    }
}

struct SessionRowView: View {
    let row: NotchIslandModel.Sessions.Row
    var showsPet = true
    /// The session the sneak shows.
    var isSelected = false
    /// A click puts it in the sneak (`NotchIslandActions.pickSession`).
    var isPickable = false
    /// "Working for 3m" on the trailing edge; the card says it its own way.
    var showsDetail = true
    /// Called with the click that picks it, after `pickSession`.
    var onPick: (() -> Void)? = nil
    @Environment(\.notchIslandActions) private var actions
    @State private var isHovering = false

    /// The row's pet: a size that sits beside 12 pt text.
    static let petPixel: CGFloat = 1.5

    var body: some View {
        if isPickable, let actions {
            // A button, not a tap gesture: VoiceOver's press (and any
            // accessibility press) reaches it too.
            Button {
                actions.pickSession(row.id)
                onPick?()
            } label: {
                content
                    .background { IslandRowHighlight(isSelected: isSelected, isHovering: isHovering) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
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
            if showsDetail {
                Text(row.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(row.status == .waiting ? Theme.islandWarning : NotchIslandStyle.reset)
                    .lineLimit(1)
                    .fixedSize()
            }
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
