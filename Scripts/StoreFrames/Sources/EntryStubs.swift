import Foundation
import UsageKit
import WidgetKit
struct AllAccountsEntry: TimelineEntry {
    struct Row: Identifiable {
        let account: ConnectedAccount
        let snapshot: UsageSnapshot?
        var id: String { account.accountID }
    }
    let date: Date
    let rows: [Row]
    let prefs: Preferences
}
struct SingleUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let accountID: String
    let kind: UsageWindow.Kind
    let accountName: String
    let prefs: Preferences
    var accountIcon: AccountIcon? = nil
    var window: UsageWindow? {
        if kind == .credits { return snapshot?.creditsWindow }
        return snapshot?.windows.first { $0.kind == kind }
    }
}
