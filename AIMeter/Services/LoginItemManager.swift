#if os(macOS)
import Foundation
import Observation
import ServiceManagement

/// "Open at Login", backed by `SMAppService.mainApp`.
///
/// There is no stored preference behind this: the registration itself is the
/// state, and the user can revoke it in System Settings → General → Login
/// Items without the app ever running. A mirrored `Bool` in the App Group
/// would just drift out of date, so the toggle reads
/// `SMAppService.mainApp.status` every time instead.
@Observable
final class LoginItemManager {
    /// Set when registering failed, so the UI can say so rather than
    /// silently snapping the toggle back.
    private(set) var lastError: String?
    /// Bumped after every change so the computed `isEnabled` re-reads.
    private var revision = 0

    /// Whether the login item is registered *and* approved. macOS shows no
    /// modal prompt for this — it adds a pending entry and surfaces a banner
    /// — so a fresh registration can sit in `.requiresApproval` until the
    /// user allows it in System Settings.
    var isEnabled: Bool {
        _ = revision
        return SMAppService.mainApp.status == .enabled
    }

    /// True while the registration exists but the user hasn't approved it.
    /// The toggle stays on (the app did its part) and the UI explains the
    /// pending step instead of pretending it worked.
    var needsApproval: Bool {
        _ = revision
        return SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        revision += 1
    }

    /// Re-reads the live status — the user may have changed it in System
    /// Settings while the app was running.
    func refreshStatus() {
        revision += 1
    }

    /// Deep link to the pane where a pending login item is approved.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
}
#endif
