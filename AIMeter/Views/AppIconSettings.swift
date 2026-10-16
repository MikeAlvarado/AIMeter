import SwiftUI
#if os(iOS)
import UIKit
#endif

/// "App icon": the notch island in four looks, a picture and a name each,
/// the one in use ringed in the accent. iOS changes the icon itself and
/// shows its own notice of the change, which no app can skip; the Mac can
/// only change the Dock's (`AppChrome.applyAppIcon`), which the footnote
/// says. See `AppIconChoice` for the names behind each look.
struct AppIconSettings: View {
    #if os(macOS)
    @Environment(PreferencesModel.self) private var prefs
    #endif
    @State private var current: AppIconChoice = .sunset
    @State private var failed = false

    /// The picture's side, and its corners in the system's own proportion.
    private static let side: CGFloat = 60
    private static let corner: CGFloat = side * 0.2237

    var body: some View {
        if Self.isAvailable {
            section
        }
    }

    /// iOS can say no to alternate icons (an iPad app running on a Mac
    /// does): then there is nothing to pick, so no card.
    private static var isAvailable: Bool {
        #if os(iOS)
        UIApplication.shared.supportsAlternateIcons
        #else
        true
        #endif
    }

    @ViewBuilder
    private var section: some View {
        SectionHeader(title: String(localized: "App icon", comment: "Settings: the section where you pick the app's icon."))
        Card {
            HStack(alignment: .top, spacing: 0) {
                ForEach(AppIconChoice.allCases) { choice in
                    if choice != AppIconChoice.allCases.first { Spacer(minLength: 8) }
                    tile(choice)
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear(perform: readCurrent)
        if let footnote {
            SectionFootnote(text: footnote)
        }
    }

    private func tile(_ choice: AppIconChoice) -> some View {
        let selected = choice == current
        return Button {
            choose(choice)
        } label: {
            VStack(spacing: 8) {
                Image(choice.previewImageName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Self.side, height: Self.side)
                    .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
                    // A hairline, so Ivory keeps an edge on a white card.
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                            .strokeBorder(Theme.ink.opacity(0.1), lineWidth: 0.5)
                    }
                    // The ring sits just outside the picture, so choosing
                    // one moves nothing.
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.corner + 4, style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: 2.5)
                            .padding(-4)
                            .opacity(selected ? 1 : 0)
                    }
                Text(choice.label)
                    .font(.footnote.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footnote: String? {
        #if os(iOS)
        failed ? String(localized: "The icon couldn't be changed.", comment: "Settings, App icon: iOS refused to switch the icon.") : nil
        #else
        String(localized: "macOS lets an app change only its Dock icon, while it runs. Finder keeps Sunset.", comment: "Settings on the Mac, App icon: what the choice changes there.")
        #endif
    }

    private func readCurrent() {
        #if os(iOS)
        current = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)
        #else
        current = prefs.appIcon
        #endif
    }

    private func choose(_ choice: AppIconChoice) {
        guard choice != current else { return }
        #if os(iOS)
        current = choice
        failed = false
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(choice.alternateIconName)
            } catch {
                // The icon iOS really shows, which a quicker second tap may
                // have changed meanwhile, rather than the one before this tap.
                current = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)
                failed = true
            }
        }
        #else
        current = choice
        prefs.appIcon = choice
        AppChrome.applyAppIcon(choice)
        #endif
    }
}
