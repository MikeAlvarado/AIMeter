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
            return model.accounts.count > 1 ? "\(usage.account.displayName) — \(values.joined(separator: ", "))" : values.joined(separator: ", ")
        }
        return lines.isEmpty ? String(localized: "AIMeter — no usage data yet") : lines.joined(separator: ". ")
    }
}
