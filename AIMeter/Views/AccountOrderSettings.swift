import SwiftUI

/// "Order by urgency" (`AccountOrder`), one row in Settings' account card
/// (under the list on iOS, under the list on the Mac's Accounts tab),
/// mirrored into the model as it changes, like "Check service status".
/// Only with accounts to order. Until 4.1 it was a section of its own
/// whose header repeated its one switch.
struct AccountOrderToggle: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    static func isOffered(_ model: UsageModel) -> Bool {
        model.accounts.count > 1
    }

    static var footnote: String {
        String(localized: "The account closest to a limit goes first, everywhere accounts are listed. Off, the order is yours: hold a card on the Dashboard and drag it.")
    }

    var body: some View {
        @Bindable var prefs = prefs

        Toggle(isOn: $prefs.ordersByUrgency) {
            Text("Order by urgency")
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.ink)
        }
        .tint(Theme.accent)
        .onChange(of: prefs.ordersByUrgency) { _, newValue in
            model.setOrdersByUrgency(newValue)
        }
    }
}
