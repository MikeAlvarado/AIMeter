import AppIntents
import SwiftUI
import UsageKit
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let accountName: String
    let prefs: Preferences
}

/// The complications: the account the user picked in the face's editor
/// (`UsageAccountConfigurationIntent`, the same picker as the phone's
/// widgets), drawn from what the iPhone last sent (`WatchStore`). Never
/// fetches: a reload only re-reads the Watch's App Group, at the same
/// floor as the phone's widgets.
struct ComplicationProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: .sample, accountName: ProviderCatalog.legacyAccount.displayName, prefs: Preferences())
    }

    func snapshot(for configuration: UsageAccountConfigurationIntent, in context: Context) async -> ComplicationEntry {
        context.isPreview ? placeholder(in: context) : entry(for: configuration)
    }

    func timeline(for configuration: UsageAccountConfigurationIntent, in context: Context) async -> Timeline<ComplicationEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(Date(timeIntervalSinceNow: AppConfig.widgetRefreshFloor)))
    }

    /// The face editor's gallery: one complication per connected account,
    /// named after it. watchOS asks for these instead of showing a picker.
    func recommendations() -> [AppIntentRecommendation<UsageAccountConfigurationIntent>] {
        let accounts = AccountRegistryStore(suiteName: AppConfig.appGroupID)?.accounts() ?? []
        return accounts.map { account in
            let intent = UsageAccountConfigurationIntent()
            intent.account = UsageAccountOption(accountID: account.accountID, accountName: account.displayName)
            return AppIntentRecommendation(intent: intent, description: Text(account.displayName))
        }
    }

    private func entry(for configuration: UsageAccountConfigurationIntent) -> ComplicationEntry {
        let (accountID, accountName) = WidgetAccountFallback.resolve(
            configured: configuration.account?.accountID, name: configuration.account?.accountName
        )
        return ComplicationEntry(
            date: .now,
            snapshot: SnapshotStore(suiteName: AppConfig.appGroupID)?.snapshot(for: accountID),
            accountName: accountName,
            prefs: Preferences.load()
        )
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .accessoryCircular:
                    CircularUsageView(snapshot: snapshot, prefs: entry.prefs)
                case .accessoryRectangular:
                    RectangularUsageView(snapshot: snapshot, prefs: entry.prefs)
                case .accessoryCorner:
                    CornerUsageView(snapshot: snapshot, prefs: entry.prefs)
                default:
                    InlineUsageView(snapshot: snapshot, prefs: entry.prefs)
                }
            } else {
                Text("Open AIMeter on iPhone")
                    .font(.caption2)
                    .minimumScaleFactor(0.6)
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

struct UsageComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppConfig.watchWidgetKind,
            intent: UsageAccountConfigurationIntent.self,
            provider: ComplicationProvider()
        ) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("Usage Limits")
        .description("Your account's limits. Edit the complication to pick which account.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
