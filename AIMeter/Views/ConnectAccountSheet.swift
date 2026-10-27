import SwiftUI
import UsageKit

/// The Connect sheet: which service, then that service's own sign-in.
/// Three families today (`ProviderCatalog.providerIDs`), each with the
/// flow its own tools use: Claude's sign-in page and the code it shows
/// (`ConnectClaudeSheet`), and a one-time device code for Codex (entered
/// on ChatGPT's device page) and GitHub Copilot (entered on GitHub's),
/// both drawn by `DeviceCodeConnectView`. Signing in again
/// (`reconnecting`) skips the picker: the account's family is known.
struct ConnectAccountSheet: View {
    /// nil for a brand-new connection; the account being repaired otherwise.
    var reconnecting: ConnectedAccount?

    @Environment(\.dismiss) private var dismiss
    @State private var pickedProviderID: String?

    var body: some View {
        switch reconnecting?.providerID ?? pickedProviderID {
        case ClaudeProvider.providerID:
            ConnectClaudeSheet(reconnecting: reconnecting)
        case CodexProvider.providerID:
            CodexConnectView(reconnecting: reconnecting)
        case CopilotProvider.providerID:
            CopilotConnectView(reconnecting: reconnecting)
        default:
            picker
        }
    }

    private var picker: some View {
        ScrollView {
            VStack(spacing: 18) {
                ProviderMark(size: 72, cornerRadius: 20, prominent: true)
                    .padding(.top, 8)

                Text("Add an account")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Text("Pick the service to connect. Each one signs in through its own page, and AIMeter only ever reads your usage limits.")
                    .font(.callout)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    ForEach(ProviderCatalog.providerIDs, id: \.self) { providerID in
                        Button {
                            pickedProviderID = providerID
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: ProviderCatalog.symbolName(for: providerID))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 36, height: 36)
                                    .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ProviderCatalog.displayName(for: providerID))
                                        .font(Theme.rowTitle)
                                        .foregroundStyle(Theme.ink)
                                    Text(Self.signInNote(for: providerID))
                                        .font(Theme.caption)
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            // The capsule is drawn outside the label: the whole
                            // row answers, not only its words.
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .background(Theme.track.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                Text("AIMeter is an independent app, not affiliated with Anthropic, OpenAI or GitHub. It only reads your own usage limits, never sends prompts or spends your plan's usage, and your sign-in tokens stay on this device.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .tapTarget()
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.bottom, 8)
            }
            .padding(24)
            #if os(macOS)
            .frame(width: 420)
            #endif
        }
        .appBackground()
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    /// The one line under a family's name: how its sign-in goes.
    static func signInNote(for providerID: String) -> String {
        switch providerID {
        case ClaudeProvider.providerID: String(localized: "Sign in on Claude's page and paste the code it shows.")
        case CodexProvider.providerID: String(localized: "Sign in with ChatGPT using a one-time code.")
        case CopilotProvider.providerID: String(localized: "Sign in with GitHub using a one-time code.")
        default: ""
        }
    }
}
