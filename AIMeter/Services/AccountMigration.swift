import Foundation
import UsageKit

/// One-time, idempotent migration from the pre-multi-account single-Claude-
/// account model to the account registry. Each step gates itself
/// independently (not one shared "migrated" flag) so a crash between steps
/// can never skip a later step on the next launch. See
/// docs/design/multi-account-plan.md for the full design.
enum AccountMigration {
    static func run(registry: AccountRegistryStore?) {
        RefreshService.migrateCredentialsToSharedGroup()
        migrateNotificationPreferencesIfNeeded()
        guard let registry else { return }
        registerLegacyManagedAccountIfNeeded(registry: registry)
    }

    /// Copies the pre-multi-account flat notification-preference keys
    /// (`notify.runout`, `notify.session`, …) to their new `"claude"`-scoped
    /// equivalents (`notify.runout.claude`, `notify.session.claude`, …) so
    /// an upgrading user's existing toggles aren't silently reset to
    /// defaults. `notify.peak` is never copied — that toggle stays global
    /// (see `NotificationPreferences`). The old flat keys are left in place,
    /// inert — deleting them buys nothing and adds a failure mode.
    private static func migrateNotificationPreferencesIfNeeded() {
        let defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
        let legacyClaude = ClaudeKeychainCredentialSource.legacyAccountID

        let globalToggleKeys = [
            "notify.runout", "notify.earlyReset",
            "notify.nearLimit", "notify.nearLimitThreshold", "notify.limitReached",
        ]
        for key in globalToggleKeys {
            copyIfNeeded(key, to: "\(key).\(legacyClaude)", in: defaults)
        }

        // Per-window reset toggles: session and weekly are always-present
        // slots; a per-model window (if this install ever had one) is read
        // from the last real snapshot rather than guessed, since its
        // storage key is account-specific (e.g. "model.Fable").
        var kinds: [UsageWindow.Kind] = [.session, .weekly]
        if let snapshot = SnapshotStore(suiteName: AppConfig.appGroupID)?.snapshot(for: legacyClaude) {
            kinds.append(contentsOf: snapshot.windows.map(\.kind))
        }
        for kind in Set(kinds) {
            let base = "notify.\(kind.storageKey)"
            copyIfNeeded(base, to: "\(base).\(legacyClaude)", in: defaults)
        }
    }

    private static func copyIfNeeded(_ oldKey: String, to newKey: String, in defaults: UserDefaults) {
        guard defaults.object(forKey: newKey) == nil,
              let value = defaults.object(forKey: oldKey) else { return }
        defaults.set(value, forKey: newKey)
    }

    /// Registers the legacy account under the literal accountID `"claude"`
    /// when the app's own Keychain already holds credentials at the
    /// default key — the iOS path, and the macOS "connected via the app's
    /// own OAuth, not Claude Code" fallback path. Deliberately does NOT
    /// probe `ClaudeCodeLocalCredentialSource` (macOS's CLI-mirrored path):
    /// that read can trigger a Keychain authorization prompt, and
    /// `RefreshService`'s existing `ClaudeAutoCredentialSource` already
    /// performs that exact read on the first refresh — this would just be a
    /// second, redundant prompt. `UsageModel` handles that case instead, by
    /// speculatively trying an `.autoDetected` "claude" account when the
    /// registry is still empty on macOS and registering it only once a
    /// refresh actually confirms real credentials.
    private static func registerLegacyManagedAccountIfNeeded(registry: AccountRegistryStore) {
        let legacyAccountID = ClaudeKeychainCredentialSource.legacyAccountID
        guard registry.account(for: legacyAccountID) == nil else { return }
        guard RefreshService.storedCredentialsExist(for: legacyAccountID) else { return }
        registry.add(ConnectedAccount(
            accountID: legacyAccountID,
            providerID: "claude",
            displayName: "Claude",
            credentialStrategy: .managed
        ))
    }
}
