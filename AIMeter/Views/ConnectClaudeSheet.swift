import SwiftUI
import UsageKit

/// OAuth connect flow: open Claude's sign-in page in the browser, the user
/// approves and copies the authentication code shown, pastes it back here,
/// and we exchange it for tokens stored in the Keychain.
///
/// Doubles as the re-sign-in flow: pass `reconnecting` and the exact same
/// exchange lands on an existing account's credential key instead of
/// creating a new account (`UsageModel.reconnect`), which is what keeps
/// that account's history, toggles, and placed widgets intact. Only the
/// copy differs, plus dropping the nickname field — the account already has
/// a name the user chose.
struct ConnectClaudeSheet: View {
    /// nil for a brand-new connection; the account being repaired otherwise.
    var reconnecting: ConnectedAccount?

    @Environment(UsageModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var session = ClaudeOAuth.startSession()
    @State private var code = ""
    @State private var nickname = ""
    @State private var isExchanging = false
    @State private var errorText: String?

    var body: some View {
        // Scrollable so content is never clipped/truncated at the `.medium`
        // detent (or with larger Dynamic Type sizes) — it just scrolls
        // instead, and dragging up to `.large` still shows it all at once.
        ScrollView {
            VStack(spacing: 18) {
                ProviderMark(size: 72, cornerRadius: 20, prominent: true)
                    .padding(.top, 8)

                Text(reconnecting == nil ? String(localized: "Connect your Claude account") : String(localized: "Sign in again"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Text(explainer)
                    .font(.callout)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    openURL(session.authorizeURL)
                } label: {
                    Label("Open Claude Sign-In", systemImage: "safari")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        // The capsule is drawn *outside* the button (below),
                        // so without this only the label's glyphs would be
                        // tappable — a `.plain` button hit-tests its label,
                        // and a transparent frame is not opaque content.
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .background(Theme.accentWash, in: Capsule())

                if reconnecting == nil, !model.accounts.isEmpty {
                    // Only relevant once there's more than one account to tell
                    // apart — a single connected account never needed a name.
                    // Never when reconnecting: that account keeps its name.
                    TextField(defaultNickname, text: $nickname)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.track.opacity(0.6), in: Capsule())
                }

                HStack(spacing: 8) {
                    TextField("Paste the code Claude shows…", text: $code)
                        .textFieldStyle(.plain)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.track.opacity(0.6), in: Capsule())

                    Button(action: pasteFromClipboard) {
                        Image(systemName: "doc.on.clipboard")
                            .accessibilityLabel(Text("Paste"))
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Theme.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button(action: connect) {
                    Group {
                        if isExchanging {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Text("Connect")
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    // Whole capsule tappable, not just the word — see the
                    // sign-in button above.
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    (canConnect ? Theme.accent : Theme.track) , in: Capsule()
                )
                .disabled(!canConnect)

                #if os(macOS)
                // macOS only, and not by accident: the iOS build never asks
                // for — or accepts — another app's credential file. Doing so
                // is what App Review guideline 5.2.2 reads as "requesting
                // third-party account information", and what Anthropic's
                // authentication policy forbids outright ("developers may
                // not collect, store, or intermediate Claude.ai
                // credentials"). On the Mac the first account already mirrors
                // Claude Code's own login by design, so this stays a
                // fallback there; see `obtainCredentials`.
                Text("You can also paste the full credentials JSON from ~/.claude/.credentials.json.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                #endif

                // Said here, at the moment of connecting, not only buried in
                // Privacy & data: what this app is, what the token is for,
                // and where it stays. Every clause must remain true to the
                // code (read-only endpoints, Keychain-only storage, no server).
                Text("AIMeter is an independent app, not affiliated with Anthropic. It only reads your own usage limits — it never sends prompts or spends your plan's usage — and your sign-in token stays on this device.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)

                if reconnecting != nil {
                    // Worth saying here specifically: signing in through this
                    // flow is also what *prevents* a repeat, and pasting the
                    // CLI's own JSON above is what invites one.
                    Text("Signing in here gives AIMeter its own token, separate from Claude Code's — so neither can invalidate the other's.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                }

                if let errorText {
                    Text(errorText)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }

                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.bottom, 8)
            }
            .padding(24)
            #if os(macOS)
            .frame(width: 420)
            #endif
        }
        .background(Theme.background)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var explainer: String {
        if reconnecting != nil {
            return String(localized: "Claude no longer accepts this account's saved sign-in. Sign in again to restore it — its history, alerts, and widgets all stay as they are.")
        }
        return String(localized: "AIMeter will open Claude's sign-in page in your browser. After you approve, copy the code it shows and paste it back here to finish. Any sign-in method works.")
    }

    private var canConnect: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isExchanging
    }

    /// Suggested name for a newly connected account — there's no email or
    /// name signal from Claude's API to derive one from, so the user has to
    /// set it (or accept this placeholder).
    private var defaultNickname: String {
        model.accounts.isEmpty ? "Claude" : "Claude \(model.accounts.count + 1)"
    }

    private var resolvedNickname: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultNickname : trimmed
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        if let pasted = UIPasteboard.general.string {
            code = pasted
        }
        #else
        if let pasted = NSPasteboard.general.string(forType: .string) {
            code = pasted
        }
        #endif
    }

    private func connect() {
        isExchanging = true
        errorText = nil
        Task {
            defer { isExchanging = false }
            do {
                let credentials = try await obtainCredentials()
                if let reconnecting {
                    await model.reconnect(accountID: reconnecting.accountID, credentials: credentials)
                } else {
                    await model.completeConnection(credentials, displayName: resolvedNickname)
                }
                if let connectionError = model.connectionError {
                    errorText = connectionError
                } else {
                    dismiss()
                }
            } catch {
                errorText = (error as? UsageError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// The field accepts the OAuth code from the sign-in page. On macOS only
    /// it also accepts a full credentials JSON copied from another machine
    /// (`~/.claude/.credentials.json`) — a fallback if the sign-in flow ever
    /// breaks. The iOS build deliberately has no such path (see the hint
    /// above): an App Store build must never take in another app's
    /// credential file, so on iOS a pasted JSON is just an invalid code.
    private func obtainCredentials() async throws -> ClaudeCredentials {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        #if os(macOS)
        if trimmed.hasPrefix("{") {
            return try ClaudeCredentials.fromClaudeCodeJSON(Data(trimmed.utf8))
        }
        #endif
        return try await ClaudeOAuth().exchange(pastedCode: trimmed, session: session)
    }
}
