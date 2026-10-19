import Foundation
import UsageKit

/// iCloud sync as the model drives it (`CloudSync`): on while
/// `Preferences.cloudSync` is, which Settings mirrors here through
/// `setCloudSync(enabled:)`; fed after every successful fetch with the
/// login's id and the account's history; the preferences on every
/// widget-visible change (`PreferencesModel.onWidgetVisibleChange`).
extension UsageModel {
    func setCloudSync(enabled: Bool) {
        if enabled {
            startCloudSync()
        } else {
            stopCloudSync(removing: true)
        }
    }

    func startCloudSync(store: CloudKeyValueStore = NSUbiquitousKeyValueStore.default) {
        guard cloud == nil else { return }
        let sync = CloudSync(store: store, timelines: timelineStore, registry: registry, defaults: Preferences.groupDefaults)
        sync.onRemoteHistory = { [weak self] accountID in self?.reloadTimeline(for: accountID) }
        sync.onRemotePreferences = { remote in
            // Through the app's model, so the open screens and the widgets
            // follow; the write echoes back here and is not sent again.
            guard let prefs = AppEnvironment.prefs else { return }
            remote.apply(to: prefs)
        }
        cloud = sync
        // A turn later, never inside `UsageModel.init`: the app's
        // `PreferencesModel` is published right after the model is made,
        // and the first pull applies another device's preferences
        // through it.
        Task { @MainActor [weak self] in
            guard let self, cloud === sync else { return }
            sync.start(preferences: Preferences.load())
        }
    }

    /// `removing`: the user turned the switch off, and what AIMeter kept
    /// in iCloud goes with it.
    func stopCloudSync(removing: Bool) {
        cloud?.stop()
        if removing { cloud?.removeAll() }
        cloud = nil
    }

    /// A fetch landed: the profile's id names the login, which is how the
    /// other devices tell this account's history from another's, and the
    /// history itself goes out soon.
    func syncToCloud(accountID: String, identity: String?) {
        guard let i = index(for: accountID) else { return }
        if let identity, accounts[i].account.syncIdentity != identity {
            accounts[i].account.syncIdentity = identity
            registry?.setSyncIdentity(identity, for: accountID)
        }
        cloud?.pushHistorySoon(for: accounts[i].account)
    }
}
