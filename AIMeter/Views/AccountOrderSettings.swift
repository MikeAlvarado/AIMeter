import SwiftUI

/// "Accounts": the one "Order by urgency" switch (`AccountOrder`),
/// mirrored into the model as it changes, like "Check service status".
/// Only with accounts to order.
struct AccountOrderSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    static func isOffered(_ model: UsageModel) -> Bool {
        model.accounts.count > 1
    }

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Accounts"))
        Card {
            Toggle(isOn: $prefs.ordersByUrgency) {
                Text("Order by urgency")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)
        }
        .onChange(of: prefs.ordersByUrgency) { _, newValue in
            model.setOrdersByUrgency(newValue)
        }
        SectionFootnote(text: String(localized: "The account closest to a limit goes first, everywhere accounts are listed. Off, the order is yours: hold a card on the Dashboard and drag it."))
    }
}
