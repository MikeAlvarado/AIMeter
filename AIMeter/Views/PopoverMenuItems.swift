#if os(macOS)
import SwiftUI

/// The menu bar popover's footer items (4.0.1): a line each, like a menu's,
/// the title at the leading edge and the shortcut or the switch at the
/// trailing one, lit while the pointer is on it the way the account rows
/// are (a faint ink fill, not a menu's accent: the popover is a panel).
struct PopoverMenuItem: View {
    let title: LocalizedStringKey
    var shortcut: String?
    let action: () -> Void

    init(_ title: LocalizedStringKey, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                if let shortcut {
                    Text(verbatim: shortcut)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .buttonStyle(PopoverMenuItemStyle())
    }
}

/// A footer item that is a switch: Discreet Mode, Open at Login. The whole
/// line flips it.
struct PopoverMenuToggle: View {
    let title: LocalizedStringKey
    var shortcut: String?
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, shortcut: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.shortcut = shortcut
        _isOn = isOn
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 12)
                if let shortcut {
                    Text(verbatim: shortcut)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Theme.accent)
            }
        }
        .buttonStyle(PopoverMenuItemStyle())
        // One switch to VoiceOver, named by the line.
        .accessibilityRepresentation {
            Toggle(title, isOn: $isOn)
        }
    }
}

/// The hairline between the footer's groups, inset like a menu's.
struct PopoverMenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Theme.ink.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
    }
}

private struct PopoverMenuItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Line(configuration: configuration)
    }

    private struct Line: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.callout)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.ink.opacity(configuration.isPressed ? 0.12 : (hovering && isEnabled ? 0.07 : 0)))
                }
                // The whole line, not just the words.
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}
#endif
