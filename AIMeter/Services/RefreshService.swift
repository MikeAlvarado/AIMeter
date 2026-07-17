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
        #if os(macOS)
        credentialSource = ClaudeAutoCredentialSource(store: Self.keychainStore)
        #else
        credentialSource = ClaudeKeychainCredentialSource(store: Self.keychainStore)
        #endif
        provider = ClaudeProvider(credentialSource: credentialSource)
        store = SnapshotStore(suiteName: AppConfig.appGroupID)
    }

    private static var keychainStore: KeychainStore {
        KeychainStore(service: AppConfig.keychainService)
    }

    func lastSnapshot() -> UsageSnapshot? {
        store?.snapshot(for: provider.id)
    }

    @discardableResult
    func refresh() async throws -> UsageSnapshot {
        let snapshot = try await provider.fetchUsage()
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
