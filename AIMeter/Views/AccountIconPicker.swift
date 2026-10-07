import SwiftUI
import UsageKit

/// The one place an account's glyph is chosen (`AccountIcon`), reached
/// from the Dashboard header's context menu ("Change icon…") and Provider
/// Detail's Account card. Three parts: the bundled marks (the default
/// sparkle, Claude, Claude Code), a curated grid of SF Symbols, and a
/// field for any symbol by name — the full catalog is Apple's SF Symbols
/// app, linked from the footnote, so the grid only has to cover the
/// obvious picks. A tap applies immediately through
/// `UsageModel.setIcon(_:for:)` (the preview at the top is the live
/// account), and Done just closes.
struct AccountIconPicker: View {
    let accountID: String

    @Environment(UsageModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var customName = ""

    /// The curated grid. Filtered at render time against what this OS
    /// actually ships, so a name missing from an older SF Symbols release
    /// just doesn't appear rather than drawing blank.
    static let curatedSymbols: [String] = [
        "sparkles", "star.fill", "bolt.fill", "brain", "cpu", "terminal",
        "chevron.left.forwardslash.chevron.right", "laptopcomputer", "desktopcomputer", "iphone",
        "briefcase.fill", "house.fill", "building.2.fill", "person.fill", "person.2.fill",
        "graduationcap.fill", "book.fill", "pencil", "paintbrush.fill", "hammer.fill",
        "wrench.and.screwdriver.fill", "flask.fill", "atom", "function", "infinity",
        "globe", "cloud.fill", "moon.fill", "sun.max.fill", "flame.fill", "leaf.fill",
        "drop.fill", "heart.fill", "gamecontroller.fill", "music.note", "camera.fill",
        "chart.bar.fill", "dollarsign.circle.fill", "cart.fill", "airplane", "car.fill",
        "pawprint.fill", "bird.fill", "tortoise.fill", "hare.fill", "shield.fill",
        "lock.fill", "key.fill", "flag.fill", "tag.fill", "bookmark.fill", "bell.fill",
        "envelope.fill", "lightbulb.fill", "command", "number", "at",
        "circle.hexagongrid.fill", "square.grid.2x2.fill",
    ]

    static let sfSymbolsURL = URL(string: "https://developer.apple.com/sf-symbols/")!

    /// Whether this OS has a symbol by that name — the gate on the free
    /// text field, so a typo can never be saved as an icon that draws
    /// nothing.
    nonisolated static func symbolExists(_ name: String) -> Bool {
        #if os(macOS)
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #else
        UIImage(systemName: name) != nil
        #endif
    }

    private var current: AccountIcon? {
        model.usage(for: accountID)?.account.icon
    }

    private var trimmedCustom: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    preview
                    SectionHeader(title: String(localized: "Marks"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    Card {
                        HStack(spacing: 14) {
                            tile(nil, label: String(localized: "Default"))
                            tile(.mark(.claude), label: "Claude")
                            tile(.mark(.claudeCode), label: "Claude Code")
                            Spacer(minLength: 0)
                        }
                    }
                    SectionHeader(title: String(localized: "Symbols"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    Card {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 10)], spacing: 10) {
                            ForEach(Self.curatedSymbols.filter(Self.symbolExists), id: \.self) { name in
                                tile(.symbol(name), label: name)
                            }
                        }
                    }
                    SectionHeader(title: String(localized: "Any symbol"))
                        .padding(.top, Theme.sectionSpacing - 10)
                    Card { customField }
                    SectionFootnote(text: String(localized: "Type any SF Symbol name. The full catalog is in Apple's SF Symbols app."))
                    Button {
                        openURL(Self.sfSymbolsURL)
                    } label: {
                        Label("Browse SF Symbols", systemImage: "arrow.up.right.square")
                            .font(Theme.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 4)
                }
                .padding(Theme.cardPadding)
            }
            .background(Theme.background)
            .navigationTitle(Text("Account icon"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 460, minHeight: 620, idealHeight: 620)
        #endif
    }

    private var preview: some View {
        VStack(spacing: 10) {
            ProviderMark(size: 72, cornerRadius: 20, icon: current)
            Text(model.usage(for: accountID)?.account.displayName ?? "")
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.ink)
            Text("Shown wherever the account appears: dashboard, menu bar, widgets, Live Activity.")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// One choice. `label` is the accessibility name only; the tile is
    /// the glyph itself, with an accent ring when it's the current pick.
    private func tile(_ icon: AccountIcon?, label: String) -> some View {
        let selected = icon == current
        return Button {
            model.setIcon(icon, for: accountID)
        } label: {
            ProviderMark(size: 48, cornerRadius: 13, icon: icon)
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Theme.accent, lineWidth: 2.5)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var customField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProviderMark(size: 36, cornerRadius: 10, icon: Self.symbolExists(trimmedCustom) ? .symbol(trimmedCustom) : nil)
                    .opacity(Self.symbolExists(trimmedCustom) ? 1 : 0.35)
                TextField(String(localized: "Symbol name, e.g. bolt.fill"), text: $customName)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.track.opacity(0.6), in: Capsule())
                    .onSubmit(applyCustom)
                Button("Use", action: applyCustom)
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .disabled(!Self.symbolExists(trimmedCustom))
            }
            if !trimmedCustom.isEmpty, !Self.symbolExists(trimmedCustom) {
                Text("No symbol with that name.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    private func applyCustom() {
        guard Self.symbolExists(trimmedCustom) else { return }
        model.setIcon(.symbol(trimmedCustom), for: accountID)
    }
}
