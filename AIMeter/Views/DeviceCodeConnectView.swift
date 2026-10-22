import SwiftUI
import UsageKit

/// One pending device-code sign-in as the view sees it: the code to show,
/// the page to type it on, how often to ask, when it dies, and the poll
/// that answers with the login once the user has approved.
struct DeviceCodePrompt {
    let userCode: String
    let verificationURL: URL
    let interval: TimeInterval
    let expiresAt: Date?
    /// nil while the user hasn't approved yet.
    let poll: () async throws -> ProviderLogin?
}

/// The device-code sign-in, the shape Codex's and GitHub Copilot's share:
/// AIMeter asks the service for a one-time code and shows it with the
/// page to type it on; the user signs in there, in their browser, never
/// in an embedded web view; the view polls until the service hands back
/// the login, then the model stores it. Nothing but the code ever
/// crosses from the browser to the app.
struct DeviceCodeConnectView: View {
    let providerID: String
    let title: String
    let explainer: String
    /// The button that opens the verification page.
    let openLabel: String
    /// A line under the code about the service's own prerequisite, if any
    /// (Codex: device code login must be allowed in ChatGPT's settings).
    var note: String?
    /// What the independence footnote says for this service.
    let footnote: String
    /// nil for a brand-new connection; the account being repaired otherwise.
    var reconnecting: ConnectedAccount?
    let start: () async throws -> DeviceCodePrompt
    /// An extra way in above the code, if the service has one (the Mac's
    /// "Use Codex's login on this Mac").
    var alternative: AnyView?

    @Environment(UsageModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private enum Phase: Equatable {
        case starting
        case waiting
        case connecting
        case failed(String)
    }

    @State private var phase: Phase = .starting
    @State private var prompt: DeviceCodePrompt?
    @State private var nickname = ""
    @State private var copied = false
    /// Bumped by "Try again": the task that asks for a code and polls is
    /// keyed on it, not on the phase, which changes while that task runs
    /// (keying on the phase cancelled the poll the moment it started).
    @State private var attempt = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ProviderMark(size: 72, cornerRadius: 20, icon: .symbol(ProviderCatalog.symbolName(for: providerID)), prominent: true)
                    .padding(.top, 8)

                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Text(explainer)
                    .font(.callout)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)

                if let alternative, reconnecting == nil {
                    alternative
                }

                codeBlock

                if let prompt {
                    Button {
                        openURL(prompt.verificationURL)
                    } label: {
                        // One line inside the capsule's ends: a longer
                        // translation shrinks a little rather than run into
                        // them (Spanish's did, on an iPhone 17).
                        Label(openLabel, systemImage: "safari")
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 13)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .background(Theme.accentWash, in: Capsule())
                }

                if let note {
                    Text(note)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                }

                if reconnecting == nil, !model.accounts.isEmpty {
                    // Only relevant once there's more than one account to tell
                    // apart; never when reconnecting (the account keeps its name).
                    TextField(defaultNickname, text: $nickname)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.track.opacity(0.6), in: Capsule())
                    if nicknameTaken {
                        Text("Another account is already called that.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                    }
                }

                Text(footnote)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)

                if case .failed(let message) = phase {
                    Text(message)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                    Button("Try again") { restart() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
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
        .appBackground()
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .task(id: attempt) {
            await run()
        }
    }

    @ViewBuilder
    private var codeBlock: some View {
        VStack(spacing: 8) {
            switch phase {
            case .starting:
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 12)
            case .waiting, .connecting, .failed:
                if let prompt {
                    HStack(spacing: 10) {
                        Text(prompt.userCode)
                            .font(.system(size: 26, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                        Button {
                            copy(prompt.userCode)
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .accessibilityLabel(Text("Copy code"))
                                .font(.body.weight(.medium))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Theme.accent, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Theme.track.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    // One VoiceOver element: "Your code: ABCD-1234".
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Your code: \(prompt.userCode)"))
                }
                if phase == .waiting || phase == .connecting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(phase == .connecting ? String(localized: "Connecting…") : String(localized: "Waiting for your approval…"))
                    }
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }

    /// Placeholder for the nickname field — see `UsageModel.suggestedNickname`.
    private var defaultNickname: String {
        model.suggestedNickname(providerID: providerID)
    }

    private var nicknameTaken: Bool {
        reconnecting == nil && model.isNameTaken(resolvedNickname)
    }

    private var resolvedNickname: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultNickname : trimmed
    }

    private func copy(_ code: String) {
        #if os(iOS)
        UIPasteboard.general.string = code
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func restart() {
        prompt = nil
        phase = .starting
        attempt += 1
    }

    /// Asks for the code, then polls at the service's interval until the
    /// login lands, the code expires, or the view goes away (the task is
    /// cancelled with it, so no poll outlives the sheet).
    private func run() async {
        do {
            let prompt = try await start()
            self.prompt = prompt
            phase = .waiting
            while !Task.isCancelled {
                if let expiresAt = prompt.expiresAt, Date() >= expiresAt {
                    phase = .failed(String(localized: "The code expired before it was entered."))
                    return
                }
                try await Task.sleep(for: .seconds(max(1, prompt.interval)))
                guard let login = try await prompt.poll() else { continue }
                phase = .connecting
                await connect(login)
                return
            }
        } catch is CancellationError {
        } catch {
            phase = .failed((error as? UsageError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func connect(_ login: ProviderLogin) async {
        if let reconnecting {
            await model.reconnect(accountID: reconnecting.accountID, login: login)
        } else {
            // A taken nickname is refused by the model as well; the field
            // says so while the poll runs, and the model picks a free one
            // if the user left it that way.
            await model.completeConnection(login, displayName: nicknameTaken ? nil : resolvedNickname)
        }
        if let connectionError = model.connectionError {
            phase = .failed(connectionError)
        } else {
            dismiss()
        }
    }
}

/// Codex: ChatGPT's device-code sign-in, the one the Codex CLI offers for
/// a terminal with no browser (`codex login --device-auth`), so it works
/// from a phone too. On the Mac the login Codex itself keeps can be
/// mirrored instead, with no sign-in at all.
struct CodexConnectView: View {
    var reconnecting: ConnectedAccount?
    @Environment(UsageModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var connectingCLI = false

    var body: some View {
        DeviceCodeConnectView(
            providerID: CodexProvider.providerID,
            title: reconnecting == nil ? String(localized: "Connect your Codex account") : String(localized: "Sign in again"),
            explainer: reconnecting == nil
                ? String(localized: "AIMeter shows you a one-time code. Open ChatGPT's device page, sign in and enter the code; the account connects as soon as you approve. Any ChatGPT plan works, Free included.")
                : String(localized: "Codex no longer accepts this account's saved sign-in. Sign in again with the code to restore it. Its history, alerts and widgets all stay as they are."),
            openLabel: String(localized: "Open ChatGPT's device page"),
            note: String(localized: "Device code sign-in has to be allowed in ChatGPT: Settings, Security, \"Allow device code login\"."),
            footnote: String(localized: "AIMeter is an independent app, not affiliated with OpenAI. It only reads your Codex limits, the same figures the CLI's /status shows, never sends prompts, and your sign-in token stays on this device."),
            reconnecting: reconnecting,
            start: {
                let auth = CodexDeviceAuth()
                let code = try await auth.requestCode()
                return DeviceCodePrompt(
                    userCode: code.userCode, verificationURL: code.verificationURL,
                    interval: code.interval, expiresAt: code.expiresAt
                ) {
                    try await auth.poll(code).map(ProviderLogin.codex)
                }
            },
            alternative: cliLogin
        )
    }

    /// macOS: the login the Codex CLI keeps in ~/.codex, mirrored
    /// read-only, the way the first Claude account mirrors Claude Code's.
    private var cliLogin: AnyView? {
        #if os(macOS)
        guard model.canConnectCodexCLILogin else { return nil }
        return AnyView(
            VStack(spacing: 6) {
                Button {
                    connectingCLI = true
                    Task {
                        await model.connectCodexCLILogin()
                        connectingCLI = false
                        if model.connectionError == nil { dismiss() }
                    }
                } label: {
                    Group {
                        if connectingCLI {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Text("Use Codex's login on this Mac")
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Theme.accent, in: Capsule())
                .disabled(connectingCLI)
                Text("Reads the login Codex keeps in ~/.codex, without changing it. Or sign in below with a code of your own.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        )
        #else
        return nil
        #endif
    }
}

/// GitHub Copilot: GitHub's device flow, asking for no scope (the quota
/// endpoint needs none and its answer carries the user id).
struct CopilotConnectView: View {
    var reconnecting: ConnectedAccount?

    var body: some View {
        DeviceCodeConnectView(
            providerID: CopilotProvider.providerID,
            title: reconnecting == nil ? String(localized: "Connect your GitHub Copilot account") : String(localized: "Sign in again"),
            explainer: reconnecting == nil
                ? String(localized: "AIMeter shows you a one-time code. Open GitHub's device page, sign in and enter the code; the account connects as soon as you approve. Copilot Free, Pro and Pro+ all work.")
                : String(localized: "GitHub no longer accepts this account's saved sign-in. Sign in again with the code to restore it. Its history, alerts and widgets all stay as they are."),
            openLabel: String(localized: "Open GitHub's device page"),
            note: nil,
            footnote: String(localized: "AIMeter is an independent app, not affiliated with GitHub. It asks GitHub for no scope at all, reads your Copilot quotas and nothing else, and your sign-in token stays on this device."),
            reconnecting: reconnecting,
            start: {
                let auth = CopilotDeviceAuth()
                let code = try await auth.requestCode()
                return DeviceCodePrompt(
                    userCode: code.userCode, verificationURL: code.verificationURL,
                    interval: code.interval, expiresAt: code.expiresAt
                ) {
                    switch try await auth.poll(code) {
                    case .pending: return nil
                    case .authorized(let credentials): return .copilot(credentials)
                    }
                }
            }
        )
    }
}
