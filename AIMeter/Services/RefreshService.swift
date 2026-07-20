import Foundation
import WidgetKit
import UsageKit

/// Fetches usage from the provider, persists the snapshot to the App Group,
/// reloads widget timelines, and reschedules reset notifications. Used by
/// the UI, the iOS background task, and the macOS refresh timer.
struct RefreshService {
    let provider: ClaudeProvider
    let credentialSource: any ClaudeCredentialSource
    private let store: SnapshotStore?

    init() {
        Self.migrateCredentialsToSharedGroup()
        #if os(macOS)
        credentialSource = ClaudeAutoCredentialSource(store: Self.keychainStore)
        #else
        credentialSource = ClaudeKeychainCredentialSource(store: Self.keychainStore)
        #endif
        provider = ClaudeProvider(credentialSource: credentialSource)
        store = SnapshotStore(suiteName: AppConfig.appGroupID)
    }

    private static var keychainStore: KeychainStore {
        KeychainStore(service: AppConfig.keychainService, accessGroup: AppConfig.keychainAccessGroup)
    }

    /// One-time move of credentials saved before keychain sharing into the
    /// shared access group, so the widget extension can read them too.
    private static func migrateCredentialsToSharedGroup() {
        guard AppConfig.keychainAccessGroup != nil else { return }
        let legacy = KeychainStore(service: AppConfig.keychainService)
        let key = ClaudeKeychainCredentialSource.defaultKey
        guard (try? keychainStore.data(for: key)) == nil,
              let data = try? legacy.data(for: key), !data.isEmpty else { return }
        try? legacy.delete(key)
        try? keychainStore.set(data, for: key)
    }

    func lastSnapshot() -> UsageSnapshot? {
        store?.snapshot(for: provider.id)
    }

    @discardableResult
    func refresh() async throws -> UsageSnapshot {
        let snapshot = try await provider.fetchUsage()
            .fillingMissingResets(from: store?.snapshot(for: provider.id))
        try store?.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        await NotificationScheduler.reschedule(for: snapshot, preferences: NotificationPreferences())
        return snapshot
    }

    // MARK: - Connection management (in-app OAuth flow)

    static func storedCredentialsExist() -> Bool {
        (try? keychainStore.data(for: ClaudeKeychainCredentialSource.defaultKey)) != nil
    }

    func storeConnection(_ credentials: ClaudeCredentials) async throws {
        try await credentialSource.save(credentials)
    }

    func disconnect() throws {
        #if os(macOS)
        try (credentialSource as? ClaudeAutoCredentialSource)?.clear()
        #else
        try (credentialSource as? ClaudeKeychainCredentialSource)?.clear()
        #endif
        store?.removeSnapshot(for: provider.id)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
