import Foundation
import WidgetKit
import UsageKit

/// Display order and nicknames — what an account is *called* and where it
/// sits, never what it is. See the type doc in `UsageModel.swift`.
extension UsageModel {
    // MARK: Ordering

    /// Moves an account so it takes `targetID`'s place — what a dashboard
    /// drag-and-drop performs, once, on drop. Registry order *is* display
    /// order for every surface (dashboard, macOS menu bar popover, the
    /// all-accounts widget, and each widget's account picker), so this one
    /// write reorders them all. It also decides which account the macOS
    /// status item falls back to when no `primaryAccountID` is set:
    /// whichever ends up first.
    @discardableResult
    func moveAccount(_ accountID: String, onto targetID: String) -> Bool {
        guard accountID != targetID,
              let from = index(for: accountID),
              let to = index(for: targetID) else { return false }
        move(from: from, to: to)
        return true
    }

    /// One step up (-1) or down (+1) — the same reorder from the header's
    /// context menu, for anyone who can't drag (VoiceOver, Switch Control,
    /// or simply preferring a menu).
    func moveAccount(_ accountID: String, by offset: Int) {
        guard let from = index(for: accountID), accounts.indices.contains(from + offset) else { return }
        move(from: from, to: from + offset)
    }

    /// Deliberately hand-rolled rather than SwiftUI's
    /// `move(fromOffsets:toOffset:)`: this is a service type, and pulling
    /// SwiftUI into it just for an array shuffle isn't worth it. `to` is a
    /// destination *index* (post-removal), not an insertion offset.
    ///
    /// Both entry points are a single discrete action (a completed drop, a
    /// menu tap), so persisting and reloading widget timelines here is
    /// exactly once per reorder — which is what keeps this clear of the
    /// per-kind WidgetKit refresh budget the rest of the app depends on.
    private func move(from: Int, to: Int) {
        guard !isDemoMode, accounts.indices.contains(from), accounts.indices.contains(to) else { return }
        let moved = accounts.remove(at: from)
        accounts.insert(moved, at: min(to, accounts.count))
        registry?.replaceAll(accounts.map(\.account))
        // The all-accounts widget renders the registry in order, so it has
        // to re-render for the new one to show up there too.
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Naming

    /// Whether an account other than `excluding` already goes by `name`
    /// (trimmed, case-insensitive). The nickname is the only thing telling
    /// accounts apart in widget pickers and notification titles, so two
    /// sharing one would be indistinguishable exactly where it matters —
    /// the rename alert and the Connect sheet both gate on this, and
    /// `rename`/`completeConnection` back them up.
    func isNameTaken(_ name: String, excluding accountID: String? = nil) -> Bool {
        let candidate = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return accounts.contains {
            $0.account.accountID != accountID
                && $0.account.displayName.localizedCaseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    /// Placeholder for a new account's nickname — there's no email or name
    /// signal from Claude's API to derive one from, so the user sets it or
    /// accepts this. "Claude" for the first account, then the first free
    /// "Claude N" counting from how many exist, skipping any a rename has
    /// already taken.
    func suggestedNickname() -> String {
        guard !accounts.isEmpty else { return "Claude" }
        var n = accounts.count + 1
        while isNameTaken("Claude \(n)") { n += 1 }
        return "Claude \(n)"
    }

    /// Renames an account in place — the nickname is the one thing about
    /// an account the user can change after connecting, and everything
    /// keyed by `accountID` (snapshot, history, notification toggles, Live
    /// Activity toggle, placed widgets) is untouched: a rename is never a
    /// reconnect. The name is cached in more places than the registry,
    /// though, so each is nudged here rather than left to drift until the
    /// next fetch: the per-account `RefreshService` (it feeds the Live
    /// Activity's name on every fetch), every placed widget, a Live
    /// Activity already running under the old name, and the reset/run-out
    /// notifications already queued with the old nickname in their title.
    /// An empty name (after trimming) or one another account already uses
    /// is rejected and returns `false` — the rename alert disables Save for
    /// both, but alert buttons don't re-evaluate `.disabled` live on every
    /// OS version, so the alert also reads this result to re-present itself
    /// with the reason instead of dismissing silently. An unchanged name
    /// is not a rejection.
    @discardableResult
    func rename(_ accountID: String, to newName: String) -> Bool {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isDemoMode, let i = index(for: accountID) else { return true }
        guard !name.isEmpty, !isNameTaken(name, excluding: accountID) else { return false }
        guard accounts[i].account.displayName != name else { return true }
        accounts[i].account.displayName = name
        // A no-op for macOS's still-speculative auto-detect candidate,
        // which isn't registered until a fetch confirms it —
        // `refresh(accountID:)` registers the in-memory (already renamed)
        // account at that point.
        registry?.rename(accountID, to: name)
        services[accountID] = services[accountID]?.renamed(to: name)
        propagateName(accountID: accountID)
        return true
    }

    /// Pushes an account's *current* nickname to the surfaces that cache
    /// it outside `accounts`: every placed widget (headers and the
    /// all-accounts widget read the name from the registry; one discrete
    /// reload, same as a reorder), a Live Activity already running under
    /// the old name, and the reset/run-out notifications already queued
    /// with the old nickname in their title. Called by `rename` itself and
    /// again by `refresh(accountID:)` when it finds a rename landed while
    /// its fetch was in flight — that fetch re-synced the activity and
    /// re-issued the notifications from the name it started with.
    func propagateName(accountID: String) {
        guard let usage = usage(for: accountID) else { return }
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        LiveActivityManager.rename(
            accountID: accountID, accountName: usage.account.displayName, snapshot: usage.snapshot,
            enabled: LiveActivityPreferences(accountID: accountID).enabled
        )
        #endif
        let label = accountLabel(for: accountID)
        Task { await services[accountID]?.rescheduleNotifications(accountLabel: label) }
    }

    /// The nickname prefix on notification titles exists only once two or
    /// more accounts are connected (`accountLabel(for:)`), so crossing that
    /// line in either direction changes the copy of every *other*
    /// account's already-queued reset/run-out requests. Re-issues them
    /// from the stored snapshots, no fetch — the same nudge a rename gives
    /// one account, applied to all but `accountID`.
    func relabelPendingNotifications(except accountID: String? = nil) {
        for entry in accounts where entry.account.accountID != accountID {
            let id = entry.account.accountID
            let label = accountLabel(for: id)
            Task { await services[id]?.rescheduleNotifications(accountLabel: label) }
        }
    }
}
