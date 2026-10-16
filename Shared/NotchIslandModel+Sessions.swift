import Foundation
import UsageKit

extension NotchIslandModel {
    /// Claude Code's sessions on this Mac as the island shows them (see
    /// "Claude Code sessions" in the repo-root CLAUDE.md): a pixel pet for
    /// each one beside the notch (or, with pets off, a mark and a count),
    /// and the expanded island's rows. Pure, like the rest of the model;
    /// the sessions come from `ClaudeSessionMonitor`, already ordered and
    /// aged by UsageKit's `ClaudeCodeSessionTracker`.
    struct Sessions: Equatable {
        /// The mark beside the notch, by urgency: a session waiting for
        /// permission, then one that finished a moment ago, then any at work.
        enum Mark: Equatable { case waiting, finished, working }

        struct Row: Equatable, Identifiable {
            enum Status: Equatable { case working, waiting, finished }
            let id: String
            let name: String
            /// The session's folder, after its title when it has one.
            let project: String?
            let status: Status
            /// "Working for 3m", "Needs permission", "Done 2m ago".
            let detail: String
            let pet: SessionPet

            var pose: SessionPet.Pose {
                switch status {
                case .working: .working
                case .waiting: .waiting
                case .finished: .asleep
                }
            }

            var accessibilityLabel: String {
                "\(name), \(detail)"
            }
        }

        /// One pet beside the notch.
        struct PetSlot: Equatable, Identifiable {
            let id: String
            let pet: SessionPet
            let pose: SessionPet.Pose
        }

        /// Nil when nothing works, waits or just finished: the bare notch.
        let mark: Mark?
        /// Sessions working or waiting, the figure beside the mark.
        let activeCount: Int
        let rows: [Row]
        /// The visible sessions past `maxRows`.
        let moreCount: Int
        /// Pets beside the notch rather than the mark and the count.
        let showsPets: Bool
        /// The sessions at work or waiting, the most urgent first: those
        /// waiting for permission, then those at work (newest turn first),
        /// then the one that just finished, asleep for its few seconds. At
        /// most `maxPets`, split across the notch (`leftPets`,
        /// `rightPets`) with the count after the right ones, the way Vibe
        /// Island's compact island reads: its pet at one end, the count at
        /// the other.
        let pets: [PetSlot]
        let morePets: Int
        /// The lead session's name beside its pet while collapsed
        /// (`claudeSessionsShowsName`, off by default), rather than the
        /// pets alone.
        let showsName: Bool
        /// The lead session, the first pet's: its row (name, folder,
        /// "Working for 3m"), which the peek shows in full.
        let lead: Row?
        /// The sessions working or waiting, in the island's own order: what
        /// a swipe goes through (`NotchIslandModel.rotation(by:)`).
        let rotation: [String]

        static let maxRows = 5
        static let maxPets = 3
        static let none = Sessions(sessions: [], justFinished: nil, now: .distantPast)

        /// `pick` is the session the user put in the sneak; `askedAt`, when
        /// each session waiting for permission asked
        /// (`ClaudeSessionMonitor.askedAt`).
        init(
            sessions: [ClaudeCodeSessionActivity],
            justFinished: ClaudeCodeSessionActivity?,
            showsPets: Bool = true,
            showsName: Bool = false,
            pick: SessionPick? = nil,
            askedAt: [String: Date] = [:],
            now: Date
        ) {
            activeCount = sessions.filter(\.isActive).count
            let waiting = sessions.contains { session in
                if case .needsPermission = session.state { return true }
                return false
            }
            if waiting {
                mark = .waiting
            } else if justFinished != nil {
                mark = .finished
            } else if activeCount > 0 {
                mark = .working
            } else {
                mark = nil
            }
            self.showsPets = showsPets
            self.showsName = showsName
            // Dealt over every session shown, so a session's pet is the same
            // beside the notch and in its row.
            let dealt = SessionPet.deal(sessions.map(\.id) + [justFinished?.id].compactMap { $0 })
            let pet = { (id: String) in dealt[id] ?? SessionPet(index: SessionPet.naturalIndex(for: id)) }
            rows = sessions.prefix(Self.maxRows).map { Self.row(for: $0, pet: pet($0.id), now: now) }
            moreCount = max(0, sessions.count - Self.maxRows)
            var slots = sessions.compactMap { session -> PetSlot? in
                switch session.state {
                case .working: PetSlot(id: session.id, pet: pet(session.id), pose: .working)
                case .needsPermission: PetSlot(id: session.id, pet: pet(session.id), pose: .waiting)
                case .finished: nil
                }
            }
            slots = Self.ordered(slots, pick: pick, askedAt: askedAt)
            rotation = sessions.filter(\.isActive).map(\.id)
            if let justFinished, !slots.contains(where: { $0.id == justFinished.id }) {
                slots.append(PetSlot(id: justFinished.id, pet: pet(justFinished.id), pose: .asleep))
            }
            pets = Array(slots.prefix(Self.maxPets))
            morePets = max(0, slots.count - Self.maxPets)
            let shown = sessions + [justFinished].compactMap { $0 }
            lead = slots.first.flatMap { slot in
                shown.first { $0.id == slot.id }.map { Self.row(for: $0, pet: slot.pet, now: now) }
            }
        }

        /// The pets on the notch's left, the lead first, and on its right,
        /// before the count. With the name shown, the lead alone sits on
        /// the left beside it; without, as even as the count allows, so the
        /// two sides come out about as wide (the lead alone on the left
        /// with one or two pets, the lead and the next with three).
        var leftPets: [PetSlot] { leftPets(named: showsName) }
        var rightPets: [PetSlot] { rightPets(named: showsName) }
        /// The split for a layout with or without the name: the island
        /// drops the name when it would cover the menu bar's own items.
        func leftPets(named: Bool) -> [PetSlot] { Array(pets.prefix(leftPetCount(named: named))) }
        func rightPets(named: Bool) -> [PetSlot] { Array(pets.dropFirst(leftPetCount(named: named))) }
        private func leftPetCount(named: Bool) -> Int { named || pets.count <= 2 ? 1 : 2 }
        /// Who leads beside the notch: a session that asked for permission
        /// after the user's last pick (every waiting one, with no pick),
        /// since it is the one that needs the user; then the session the
        /// user picked, while it works or waits; then the rest, those
        /// waiting first, so a waiting session is never left in the count
        /// past `maxPets`. Once the newer request is answered, the pick
        /// leads again.
        static func ordered(_ slots: [PetSlot], pick: SessionPick?, askedAt: [String: Date]) -> [PetSlot] {
            let waiting = slots.filter { $0.pose == .waiting }
            var ordered = waiting.filter { slot in
                guard let pick else { return true }
                return (askedAt[slot.id] ?? .distantPast) > pick.at
            }
            if let pick, let picked = slots.first(where: { $0.id == pick.id }), !ordered.contains(picked) {
                ordered.append(picked)
            }
            ordered += waiting.filter { !ordered.contains($0) }
            ordered += slots.filter { !ordered.contains($0) }
            return ordered
        }

        /// Every session a pet stands for, shown or past `maxPets`: the
        /// count on the notch's right.
        var count: Int { pets.count + morePets }

        var isEmpty: Bool { rows.isEmpty }

        /// What VoiceOver says for the mark and the count.
        var markLabel: String? {
            switch mark {
            case .waiting: String(localized: "A Claude Code session needs permission")
            case .finished: String(localized: "A Claude Code session finished")
            case .working: String(localized: "Claude Code sessions working: \(activeCount)")
            case nil: nil
            }
        }

        static func row(for session: ClaudeCodeSessionActivity, pet: SessionPet, now: Date) -> Row {
            let status: Row.Status
            let detail: String
            switch session.state {
            case .working(let since):
                status = .working
                detail = now.timeIntervalSince(since) < 60
                    ? String(localized: "Working")
                    : String(localized: "Working for \(UsageFormatting.relativeString(from: since, to: now))")
            case .needsPermission:
                status = .waiting
                detail = String(localized: "Needs permission")
            case .finished(let at):
                status = .finished
                detail = now.timeIntervalSince(at) < 60
                    ? String(localized: "Done just now")
                    : String(localized: "Done \(UsageFormatting.relativeString(from: at, to: now)) ago")
            }
            return Row(
                id: session.id,
                name: session.name,
                project: session.title == nil ? nil : session.project,
                status: status,
                detail: detail,
                pet: pet
            )
        }
    }
}

extension NotchIslandModel {
    /// The session the user put in the sneak (a click on its pet or row,
    /// or a swipe), and when: a session that asks for permission after
    /// that still takes the sneak (`Sessions.ordered`).
    struct SessionPick: Equatable {
        let id: String
        let at: Date
    }

    /// What a swipe across the island brings into the sneak.
    enum Rotation: Equatable {
        case session(String)
        case account(String)
    }

    /// The next (`step` 1) or previous (-1) of what the sneak shows: while
    /// a session works, waits or just finished, only the sessions turn;
    /// otherwise the accounts, in the registry's order. Nil with fewer
    /// than two to turn through.
    func rotation(by step: Int) -> Rotation? {
        if sessions.mark != nil {
            return Self.rotated(sessions.rotation, from: sessions.lead?.id, by: step).map(Rotation.session)
        }
        return Self.rotated(accounts.map(\.id), from: primaryID, by: step).map(Rotation.account)
    }

    /// `step` places on from `current` in `ids`, coming round at either
    /// end; from nothing listed, the first (forward) or the last.
    static func rotated(_ ids: [String], from current: String?, by step: Int) -> String? {
        guard ids.count > 1, step != 0 else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else {
            return step > 0 ? ids.first : ids.last
        }
        let count = ids.count
        return ids[((index + step) % count + count) % count]
    }
}
