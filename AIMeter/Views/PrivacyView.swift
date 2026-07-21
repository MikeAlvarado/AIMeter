import SwiftUI
import UsageKit

/// Privacy & data: where data lives, how connecting works, and exactly
/// what the connection can access. Every claim here must stay true to the
/// code — update this screen when the data flow changes.
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: String(localized: "Private by default"))
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        PrivacyRow(
                            systemName: "iphone",
                            title: String(localized: "Everything stays on your device"),
                            text: String(localized: "AIMeter has no server and no account of its own. Usage is read directly from Anthropic and cached on this device so widgets can show it. Nothing is sent anywhere else.")
                        )
                        Divider().overlay(Theme.track)
                        PrivacyRow(
                            systemName: "key.fill",
                            title: String(localized: "Tokens live in the Keychain"),
                            text: keychainRowText
                        )
                        Divider().overlay(Theme.track)
                        PrivacyRow(
                            systemName: "eye.slash.fill",
                            title: String(localized: "No tracking, no analytics"),
                            text: String(localized: "No analytics SDKs, no ad networks, no crash reporting. The app collects no data at all.")
                        )
                    }
                }

                sectionGap
                SectionHeader(title: String(localized: "How connecting works"))
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        #if os(macOS)
                        Text("On the Mac, AIMeter reads the login Claude Code already keeps on this computer — read-only. It never modifies or rotates those tokens; Claude Code stays in charge of its own session.")
                            .font(.callout)
                            .foregroundStyle(Theme.ink)
                        #else
                        Text("You sign in on Claude's own page in your browser — never an embedded web view — so AIMeter can't see your password. You only paste back the code Claude shows after you approve.")
                            .font(.callout)
                            .foregroundStyle(Theme.ink)
                        #endif
                    }
                }
                SectionFootnote(text: String(localized: "It is the same OAuth flow Claude Code itself uses; AIMeter only receives the token Claude hands back."))

                sectionGap
                SectionHeader(title: String(localized: "What the connection can access"))
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        HStack(spacing: 8) {
                            Image("ClaudeIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(verbatim: "Claude")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        Text("Requested OAuth scopes:")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSecondary)
                        HStack(spacing: 8) {
                            ScopeChip(name: "user:profile")
                            ScopeChip(name: "user:inference")
                        }
                        Text("Whatever the token could technically do, AIMeter only ever calls two read-only endpoints: your usage windows and your profile (to show the plan). It never sends prompts, never generates code, and never spends usage on your behalf — the source is open if you want to verify.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }

                sectionGap
                Card {
                    Text("AIMeter is an independent open source project (MIT). It is not affiliated with, endorsed by, or sponsored by Anthropic. \"Claude\" is a trademark of Anthropic, PBC.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle(String(localized: "Privacy & data"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var sectionGap: some View {
        Spacer().frame(height: Theme.sectionSpacing - 16)
    }

    /// The widget's Keychain access differs by platform (App Group access
    /// group on iOS; the menu bar app feeds it on macOS instead, since a
    /// sandboxed widget there can't read Claude Code's own credential
    /// file) — this row must say the true thing for whichever one is running.
    private var keychainRowText: String {
        #if os(macOS)
        String(localized: "Your sign-in token is read from the Keychain item Claude Code already keeps on this Mac — read-only, and never leaves this device. The widget doesn't access the Keychain directly; the menu bar app feeds it your usage instead.")
        #else
        String(localized: "Your sign-in token is stored encrypted in the system Keychain, shared only with the widget (through the App Group's keychain access group) so it can refresh usage by itself. It is used exclusively to read your usage.")
        #endif
    }
}

/// Icon + title + explanation row (Private by default card).
private struct PrivacyRow: View {
    let systemName: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(text)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Monospaced OAuth scope pill.
private struct ScopeChip: View {
    let name: String

    var body: some View {
        Text(verbatim: name)
            .font(.caption.monospaced())
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Theme.track.opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
