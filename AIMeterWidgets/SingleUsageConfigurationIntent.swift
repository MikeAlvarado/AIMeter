import AppIntents
import UsageKit

/// One selectable (provider, window kind) pair for the single-limit
/// widget's Edit Widget UI. Options are read from the last stored snapshot
/// so the list always matches what the account actually reports right now
/// — e.g. a Pro account with no per-model window simply offers session and
/// weekly, rather than a name baked in at build time.
struct UsageWindowOption: AppEntity {
    let providerID: String
    let kind: UsageWindow.Kind
    let providerName: String

    var id: String { "\(providerID)|\(kind.storageKey)" }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Usage Window"
    static var defaultQuery = UsageWindowOptionQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(providerName) · \(kind.shortName)")
    }

    init(providerID: String, kind: UsageWindow.Kind, providerName: String) {
        self.providerID = providerID
        self.kind = kind
        self.providerName = providerName
    }

    /// Reconstructs an option straight from its persisted `id`, so a
    /// previously chosen window still resolves even if it's since dropped
    /// out of the account's current snapshot (e.g. a plan change removed
    /// it) — the widget then simply has nothing to show for it, rather
    /// than silently reverting to a different selection.
    init?(id: String) {
        let parts = id.split(separator: "|", maxSplits: 1)
        guard parts.count == 2, let kind = UsageWindow.Kind(storageKey: String(parts[1])) else {
            return nil
        }
        let providerID = String(parts[0])
        self.init(providerID: providerID, kind: kind, providerName: Self.providerName(for: providerID))
    }

    static func providerName(for providerID: String) -> String {
        providerID == "claude" ? "Claude" : providerID.capitalized
    }
}

struct UsageWindowOptionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [UsageWindowOption] {
        identifiers.compactMap(UsageWindowOption.init(id:))
    }

    func suggestedEntities() async throws -> [UsageWindowOption] {
        currentOptions()
    }

    func defaultResult() async -> UsageWindowOption? {
        currentOptions().first
    }

    /// Options for every provider in `AppConfig.providerIDs` (just "claude"
    /// today) — the store lookup still drives each provider's own option
    /// list so it reflects whatever windows that account currently has
    /// rather than assuming a fixed set. When there's no per-model window
    /// and the credits fallback would actually show (Settings: Credits, or
    /// Auto with credits enabled), "Credits" is offered too — same rule
    /// `WindowSlots` uses for the dashboard's third slot.
    private func currentOptions() -> [UsageWindowOption] {
        let store = SnapshotStore(suiteName: AppConfig.appGroupID)
        let fallback = Preferences.load().modelSlotFallback

        return AppConfig.providerIDs.flatMap { providerID -> [UsageWindowOption] in
            let providerName = UsageWindowOption.providerName(for: providerID)
            let snapshot = store?.snapshot(for: providerID)
            let kinds = snapshot?.windows.map(\.kind) ?? []
            var resolvedKinds = kinds.isEmpty ? [.session, .weekly] : kinds

            let hasModelWindow = resolvedKinds.contains {
                if case .modelSpecific = $0 { return true }
                return false
            }
            if !hasModelWindow, fallback != .hidden, snapshot?.creditsWindow != nil {
                resolvedKinds.append(.credits)
            }

            return resolvedKinds.map { UsageWindowOption(providerID: providerID, kind: $0, providerName: providerName) }
        }
    }
}

struct SingleUsageConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Usage Window"
    static var description = IntentDescription("Choose which limit this widget shows.")

    @Parameter(title: "Limit")
    var window: UsageWindowOption?
}
