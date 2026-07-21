import SwiftUI
import UsageKit

/// OAuth connect flow: open Claude's sign-in page in the browser, the user
/// approves and copies the authentication code shown, pastes it back here,
/// and we exchange it for tokens stored in the Keychain.
struct ConnectClaudeSheet: View {
    @Environment(UsageModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var session = ClaudeOAuth.startSession()
    @State private var code = ""
    @State private var isExchanging = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 18) {
            Image("ClaudeCodeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .padding(.top, 8)

            Text("Connect Claude Code")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.ink)

            Text("AIMeter will open Claude's sign-in page in your browser. After you approve, copy the code it shows and paste it back here to finish. Any sign-in method works.")
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
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .background(Theme.accentWash, in: Capsule())

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
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                (canConnect ? Theme.accent : Theme.track) , in: Capsule()
            )
            .disabled(!canConnect)

            Text("You can also paste the full credentials JSON from ~/.claude/.credentials.json.")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)

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
        .background(Theme.background)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 420)
        #endif
    }

    private var canConnect: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isExchanging
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
                await model.completeConnection(credentials)
                if let connectionError = model.lastError {
                    errorText = connectionError
                } else {
                    dismiss()
                }
            } catch {
                errorText = (error as? UsageError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// The field accepts either the OAuth code from the sign-in page or a
    /// full credentials JSON copied from another device
    /// (`~/.claude/.credentials.json`) — a fallback if the sign-in flow
    /// ever breaks.
    private func obtainCredentials() async throws -> ClaudeCredentials {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return try ClaudeCredentials.fromClaudeCodeJSON(Data(trimmed.utf8))
        }
        return try await ClaudeOAuth().exchange(pastedCode: trimmed, session: session)
    }
}
