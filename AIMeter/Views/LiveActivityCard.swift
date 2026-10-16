#if os(iOS)
import SwiftUI
import UsageKit

/// Provider Detail's "Live Activity" card: this account's Session
/// countdown on the Lock Screen and in the Dynamic Island, and, while that
/// is on, its pet beside the countdown (see "Live Activity" in
/// `AIMeterWidgets/CLAUDE.md`). Both switches are per account and off by
/// default.
struct LiveActivityCard: View {
    let accountID: String

    @Environment(UsageModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    /// The two switches, read when the card opens and written through
    /// `LiveActivityPreferences` on every change: the pet's row shows only
    /// while the activity's switch is on, so the card has to see that
    /// switch move, which a binding straight to the App Group wouldn't tell
    /// it. No permission gate (unlike notifications).
    @State private var isOn: Bool
    @State private var showsPet: Bool

    init(accountID: String) {
        self.accountID = accountID
        let preferences = LiveActivityPreferences(accountID: accountID)
        _isOn = State(initialValue: preferences.enabled)
        _showsPet = State(initialValue: preferences.showsPet)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                Toggle(isOn: activityBinding) {
                    Text("Live Activity")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)
                if isOn {
                    Divider().overlay(Theme.track)
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: petBinding) {
                            // The pet itself beside the words, so it is clear
                            // which one this account gets.
                            HStack(spacing: 8) {
                                Text("Show a pet")
                                    .font(Theme.rowTitle)
                                    .foregroundStyle(Theme.ink)
                                let pixel = SessionPet.pixelSize(fitting: 24, displayScale: displayScale)
                                PetPixelsView(pet: SessionPet(accountID: accountID), pose: .working, pixel: pixel)
                                    .offset(y: -CGFloat(SessionPet.bodyLift) * pixel)
                            }
                        }
                        .tint(Theme.accent)
                        Text("This account's pixel pet joins the countdown: calm with room to spare, nervous near the limit.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
    }

    private var usage: UsageModel.AccountUsage? {
        model.usage(for: accountID)
    }

    private var activityBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { newValue in
                isOn = newValue
                LiveActivityPreferences(accountID: accountID).enabled = newValue
                if newValue {
                    LiveActivityManager.sync(
                        accountID: accountID,
                        accountName: accountName,
                        accountIcon: usage?.account.icon,
                        providerID: providerID,
                        snapshot: usage?.snapshot,
                        enabled: true
                    )
                } else {
                    LiveActivityManager.end(accountID: accountID)
                }
            }
        )
    }

    /// The pet rides in the activity's attributes, so a running activity
    /// restarts with it or without it; with none running, the next one
    /// simply starts that way.
    private var petBinding: Binding<Bool> {
        Binding(
            get: { showsPet },
            set: { newValue in
                showsPet = newValue
                LiveActivityPreferences(accountID: accountID).showsPet = newValue
                LiveActivityManager.restart(
                    accountID: accountID,
                    accountName: accountName,
                    accountIcon: usage?.account.icon,
                    providerID: providerID,
                    snapshot: usage?.snapshot,
                    enabled: isOn
                )
            }
        )
    }

    private var accountName: String {
        usage?.account.displayName ?? ProviderCatalog.displayName(for: ProviderCatalog.defaultProviderID)
    }

    private var providerID: String {
        usage?.account.providerID ?? ProviderCatalog.defaultProviderID
    }
}
#endif
