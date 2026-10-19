import SwiftUI

/// "iCloud": the one switch for syncing the display preferences and every
/// account's history with the user's other devices (`CloudSync`),
/// mirrored into the model as it changes, like "Check service status".
struct CloudSyncSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "iCloud"))
        Card {
            Toggle(isOn: $prefs.cloudSync) {
                Text("Sync preferences and history")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)
        }
        .onChange(of: prefs.cloudSync) { _, newValue in
            model.setCloudSync(enabled: newValue)
        }
        SectionFootnote(text: String(localized: "Your display preferences and each account's usage history reach your other devices with AIMeter through your iCloud. Logins never do: each device signs in on its own, and the same account is matched by the id your provider reports. Turning it off removes what AIMeter keeps in iCloud."))
    }
}
