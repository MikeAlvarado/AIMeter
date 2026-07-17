import SwiftUI
import UsageKit

/// Claude detail: the same windows in full, plus per-window reset
/// notifications and (iOS) disconnect.
struct ProviderDetailView: View {
    @Environment(UsageModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: String(localized: "Rate limits"))
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        WindowRowsList(snapshot: model.snapshot)
                        if let snapshot = model.snapshot {
                            Divider().overlay(Theme.track)
                            Text(UsageFormatting.updatedLabel(snapshot.fetchedAt))
                                .font(Theme.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }

                SectionHeader(title: String(localized: "Notifications"))
                    .padding(.top, Theme.sectionSpacing - 10)
                NotificationTogglesCard()
                SectionFootnote(text: String(localized: "A local notification fires when the selected usage window resets."))

                #if os(iOS)
                Button(role: .destructive) {
                    model.disconnect()
                    dismiss()
                } label: {
                    Text("Disconnect Claude")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .padding(.top, Theme.sectionSpacing - 10)
                #endif
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Claude")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Per-window notification toggles over the three fixed slots.
struct NotificationTogglesCard: View {
    @Environment(UsageModel.self) private var model

    var body: some View {
        Card {
            VStack(spacing: Theme.rowSpacing) {
                let slots = WindowSlots(snapshot: model.snapshot).slots
                ForEach(Array(slots.enumerated()), id: \.element.kind) { index, slot in
                    if index > 0 {
                        Divider().overlay(Theme.track)
                    }
                    Toggle(isOn: binding(for: slot.kind)) {
                        Text(slot.kind.displayName)
                            .font(Theme.rowTitle)
                            .foregroundStyle(slot.window == nil ? Theme.inkSecondary : Theme.ink)
                    }
                    .tint(Theme.accent)
                    .disabled(slot.window == nil)
                }
            }
        }
    }

    private func binding(for kind: UsageWindow.Kind) -> Binding<Bool> {
        Binding(
            get: { model.notificationsEnabled(for: kind) },
            set: { model.setNotificationsEnabled($0, for: kind) }
        )
    }
}
