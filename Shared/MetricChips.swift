import SwiftUI
import UsageKit

/// Multi-select row of window chips — toggles membership in `selection`,
/// keeping the options' own order, never fewer than one nor more than
/// `maxCount`. Shared by the menu bar's `multi` style and the notch
/// island's wings, which list windows under the same 1–3 rule.
struct MetricChips: View {
    let options: [UsageWindow.Kind]
    @Binding var selection: [UsageWindow.Kind]
    var maxCount = MenuBarLabelModel.maxMetrics

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { kind in
                let isOn = selection.contains(kind)
                Button {
                    toggle(kind)
                } label: {
                    Text(kind.shortName)
                        .font(.subheadline.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Theme.ink : Theme.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isOn ? Theme.accentWash : Theme.track.opacity(0.6), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func toggle(_ kind: UsageWindow.Kind) {
        if selection.contains(kind) {
            guard selection.count > 1 else { return }
            selection.removeAll { $0 == kind }
        } else {
            guard selection.count < maxCount else { return }
            selection = options.filter { selection.contains($0) || $0 == kind }
        }
    }
}
