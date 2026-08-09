#if os(iOS)
import AppIntents
import WidgetKit
import UsageKit

/// Interactive widget button action: force a fetch for one account right
/// now, then reload the widget's timeline so the tap shows fresh data
/// within a couple seconds. iOS only — a sandboxed macOS widget can't read
/// Claude Code's credential file, so the menu bar app feeds it instead (see
/// `WidgetRefresher`); there's nothing for a macOS tap to fetch with.
///
/// Internal to the widget's own button, not a standalone Shortcuts/Siri
/// action.
struct RefreshAccountIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Account")
    var accountID: String

    init() {}

    init(accountID: String) {
        self.accountID = accountID
    }

    func perform() async throws -> some IntentResult {
        _ = await WidgetRefresher.refreshNow(accountID: accountID)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.allAccountsWidgetKind)
        return .result()
    }
}
#endif
