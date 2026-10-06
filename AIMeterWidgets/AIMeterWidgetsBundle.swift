import SwiftUI
import WidgetKit

@main
struct AIMeterWidgetsBundle: WidgetBundle {
    // Gallery order: the account's limits first (the widget most people
    // place), then the one-number variant, then every account at once.
    var body: some Widget {
        UsageWidget()
        SingleUsageWidget()
        AllAccountsWidget()
        #if os(iOS)
        SessionLiveActivity()
        #endif
    }
}
