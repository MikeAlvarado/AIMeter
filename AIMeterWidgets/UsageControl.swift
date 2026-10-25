#if os(iOS)
import AppIntents
import SwiftUI
import UsageKit
import WidgetKit

/// The control (iOS 18 and later) for Control Center, the Lock Screen's
/// two buttons and the Action button: one account's figure, the same
/// window the Lock Screen gauge reads (`glanceMetric`), and a tap that
/// refreshes it (`RefreshAccountIntent`, the widgets' own button). The
/// account is the control's to pick, like a widget's; unset, the first
/// connected one. It reads the App Group's snapshot and never fetches by
/// itself: the app and the widgets keep the snapshot fresh.
@available(iOS 18.0, *)
struct UsageControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: AppConfig.controlKind, provider: Provider()) { value in
            ControlWidgetButton(action: RefreshAccountIntent(accountID: value.accountID)) {
                Label {
                    Text(value.title)
                    Text(value.figure)
                } icon: {
                    Image(systemName: "gauge.with.needle", variableValue: value.fraction)
                }
            } actionLabel: { isActive in
                if isActive {
                    Label("Refreshing", systemImage: "arrow.clockwise")
                } else {
                    Label {
                        Text(value.title)
                        Text(value.figure)
                    } icon: {
                        Image(systemName: "gauge.with.needle", variableValue: value.fraction)
                    }
                }
            }
        }
        .displayName("Usage")
        .description("One account's figure. A tap refreshes it.")
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: UsageControlConfigurationIntent) -> ControlFigure {
            ControlFigure(accountID: ProviderCatalog.legacyAccount.accountID, name: "AIMeter", snapshot: .sample, prefs: Preferences())
        }

        func currentValue(configuration: UsageControlConfigurationIntent) async throws -> ControlFigure {
            let account = WidgetAccountFallback.resolve(configured: configuration.account?.accountID, name: configuration.account?.accountName)
            let snapshot = SnapshotStore(suiteName: AppConfig.appGroupID)?.snapshot(for: account.accountID)
            return ControlFigure(accountID: account.accountID, name: account.accountName, snapshot: snapshot, prefs: Preferences.load())
        }
    }
}

/// The control's account, picked in the control's own settings.
@available(iOS 18.0, *)
struct UsageControlConfigurationIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Account"
    static var description = IntentDescription("Choose which connected account this control shows.")

    @Parameter(title: "Account")
    var account: UsageAccountOption?

    init() {}
}
#endif
