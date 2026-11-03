import AppIntents
import UsageKit

/// Shortcuts / Siri: fetch every connected account now and say what came
/// back. On the Mac this is also the sanctioned way to a system-wide key
/// — assign one to the shortcut in the Shortcuts app — without the
/// Accessibility permission a global hotkey of the app's own would need
/// (see "macOS hiding & re-entry" in AIMeter/CLAUDE.md).
struct RefreshUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Usage"
    static var description = IntentDescription("Fetches the latest usage for every connected account and updates the widgets.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = AppEnvironment.shared else {
            return .result(dialog: "AIMeter isn't running.")
        }
        await model.refreshAll()
        return .result(dialog: IntentDialog(stringLiteral: UsageSummary.spoken(for: model)))
    }
}

/// Opens the dashboard (reopening the window even when the Dock icon is
/// hidden and the window was closed at launch).
struct ShowUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Usage"
    static var description = IntentDescription("Opens AIMeter's dashboard.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if os(macOS)
        AppChrome.revealMainWindow()
        #endif
        return .result()
    }
}

struct AIMeterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshUsageIntent(),
            phrases: ["Refresh usage in \(.applicationName)", "Update \(.applicationName)"],
            shortTitle: "Refresh Usage",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: ShowUsageIntent(),
            phrases: ["Show my usage in \(.applicationName)", "Open \(.applicationName)"],
            shortTitle: "Show Usage",
            systemImageName: "gauge.with.needle"
        )
        AppShortcut(
            intent: AccountUsageIntent(),
            phrases: ["How much of \(\.$account) have I used in \(.applicationName)", "\(\.$account) usage in \(.applicationName)"],
            shortTitle: "Account Usage",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: NextResetsIntent(),
            phrases: ["When does \(\.$account) reset in \(.applicationName)", "Next resets in \(.applicationName)"],
            shortTitle: "Next Resets",
            systemImageName: "arrow.circlepath"
        )
        AppShortcut(
            intent: OpenAccountIntent(),
            phrases: ["Open \(\.$account) in \(.applicationName)"],
            shortTitle: "Open Account",
            systemImageName: "person.crop.circle"
        )
    }
}

/// One line per account for the intent's dialog: "Work — Session 42% used,
/// Week 18% used".
enum UsageSummary {
    @MainActor
    static func spoken(for model: UsageModel) -> String {
        let mode = Preferences.load().displayMode
        let lines = model.accounts.compactMap { usage -> String? in
            guard let snapshot = usage.snapshot else { return nil }
            let kinds = UsageSnapshot.glanceOptions(for: snapshot, modelSlotFallback: .hidden)
            let values = kinds.compactMap { kind in
                snapshot.window(for: kind).map { "\(kind.shortName) \(Int($0.displayedPct(mode)))% \(mode.label.lowercased())" }
            }
            return model.accounts.count > 1 ? "\(usage.account.displayName): \(values.joined(separator: ", "))" : values.joined(separator: ", ")
        }
        return lines.isEmpty ? String(localized: "AIMeter: no usage data yet") : lines.joined(separator: ". ")
    }

    /// One account's windows with their figures: "Work: Session 42% used,
    /// Week 18% used".
    @MainActor
    static func figures(accountID: String, in model: UsageModel) -> String {
        guard let usage = model.usage(for: accountID), let snapshot = usage.snapshot else {
            return String(localized: "AIMeter: no usage data yet")
        }
        let mode = Preferences.load().displayMode
        let values = snapshot.windows.map { "\($0.shortTitle) \(Int($0.displayedPct(mode)))% \(mode.label.lowercased())" }
        return "\(usage.account.displayName): \(values.joined(separator: ", "))"
    }

    /// When each of one account's windows resets: "Work: Session resets
    /// in 2h 10m. Week resets in 3d 4h." A window with no reset ahead (an
    /// idle session) is left out.
    @MainActor
    static func resets(accountID: String, in model: UsageModel, now: Date = Date()) -> String {
        guard let usage = model.usage(for: accountID), let snapshot = usage.snapshot else {
            return String(localized: "AIMeter: no usage data yet")
        }
        let lines = snapshot.windows.compactMap { window -> String? in
            guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
            let value = UsageFormatting.resetValue(for: resetsAt, style: .relative, now: now)
            return String(localized: "\(window.shortTitle) resets in \(value).")
        }
        guard !lines.isEmpty else {
            return String(localized: "\(usage.account.displayName): no reset ahead.")
        }
        return "\(usage.account.displayName): \(lines.joined(separator: " "))"
    }
}
