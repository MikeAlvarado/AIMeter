import XCTest
import UsageKit
@testable import AIMeter

/// The second and third provider families: what the catalog builds for
/// them, how the slots and the glance surfaces read a snapshot that has
/// no session, and the titles a window's own length gives it.
final class ProviderCatalogMultiProviderTests: XCTestCase {
    private let keychain = KeychainStore(service: "aimeter.tests")

    func testTheThreeFamiliesHaveNamesAndGlyphs() {
        XCTAssertEqual(ProviderCatalog.providerIDs, ["claude", "codex", "copilot"])
        XCTAssertEqual(ProviderCatalog.displayName(for: CodexProvider.providerID), "Codex")
        XCTAssertEqual(ProviderCatalog.displayName(for: CopilotProvider.providerID), "GitHub Copilot")
        XCTAssertEqual(ProviderCatalog.symbolName(for: ClaudeProvider.providerID), ProviderMark.defaultSymbol)
        XCTAssertNotEqual(ProviderCatalog.symbolName(for: CodexProvider.providerID), ProviderCatalog.symbolName(for: CopilotProvider.providerID))
    }

    func testMakeProviderBuildsCodexAndCopilot() {
        var codex = ConnectedAccount.managed("c1", name: "Codex")
        codex = ConnectedAccount(accountID: codex.accountID, providerID: CodexProvider.providerID, displayName: codex.displayName, credentialStrategy: .managed)
        let codexBundle = ProviderCatalog.makeProvider(for: codex, keychain: keychain)
        XCTAssertTrue(codexBundle.provider is CodexProvider)
        XCTAssertTrue(codexBundle.credentials is CodexKeychainCredentialSource)
        XCTAssertEqual(codexBundle.provider.id, "codex")

        let copilot = ConnectedAccount(accountID: "g1", providerID: CopilotProvider.providerID, displayName: "Copilot", credentialStrategy: .managed)
        let copilotBundle = ProviderCatalog.makeProvider(for: copilot, keychain: keychain)
        XCTAssertTrue(copilotBundle.provider is CopilotProvider)
        XCTAssertTrue(copilotBundle.credentials is CopilotKeychainCredentialSource)
        XCTAssertEqual(copilotBundle.provider.id, "copilot")
    }

    #if os(macOS)
    func testAnAutoDetectedCodexAccountMirrorsTheCLIsFile() {
        let account = ConnectedAccount(accountID: "c2", providerID: CodexProvider.providerID, displayName: "Codex", credentialStrategy: .autoDetected)
        let bundle = ProviderCatalog.makeProvider(for: account, keychain: keychain)
        XCTAssertTrue(bundle.credentials is CodexFileCredentialSource)
    }
    #endif

    func testEveryFamilyHasAStatusPage() {
        XCTAssertTrue(ProviderCatalog.statusSource(for: CodexProvider.providerID) is StatuspageSource)
        XCTAssertTrue(ProviderCatalog.statusSource(for: CopilotProvider.providerID) is StatuspageSource)
        XCTAssertEqual(ProviderCatalog.statusPageURL(for: CodexProvider.providerID)?.host, "status.openai.com")
        XCTAssertEqual(ProviderCatalog.statusPageURL(for: CopilotProvider.providerID)?.host, "www.githubstatus.com")
        XCTAssertNil(ProviderCatalog.statusSource(for: "nobody"))
    }

    func testAProviderLoginKnowsItsFamily() {
        XCTAssertEqual(ProviderLogin.claude(ClaudeCredentials(accessToken: "t")).providerID, "claude")
        XCTAssertEqual(ProviderLogin.codex(CodexCredentials(accessToken: "t")).providerID, "codex")
        XCTAssertEqual(ProviderLogin.copilot(CopilotCredentials(accessToken: "t")).providerID, "copilot")
    }
}

final class WindowSlotsMultiProviderTests: XCTestCase {
    private let now = Date()
    private let month: TimeInterval = 30 * 86400

    private func copilot() -> UsageSnapshot {
        UsageSnapshot(providerID: "copilot", planName: "Free", windows: [
            UsageWindow(kind: .quota("premium_interactions"), usedPct: 38, resetsAt: now.addingTimeInterval(5 * 86400), duration: month),
            UsageWindow(kind: .quota("chat"), usedPct: 20, resetsAt: now.addingTimeInterval(5 * 86400), duration: month),
            UsageWindow(kind: .quota("completions"), usedPct: 4, resetsAt: now.addingTimeInterval(5 * 86400), duration: month),
            UsageWindow(kind: .quota("extra"), usedPct: 1, duration: month),
        ])
    }

    private func codexFree() -> UsageSnapshot {
        UsageSnapshot(providerID: "codex", planName: "free", windows: [
            UsageWindow(kind: .weekly, usedPct: 12, resetsAt: now.addingTimeInterval(20 * 86400), duration: month),
        ])
    }

    func testQuotasFillTheSlotsWhenThereIsNoRateWindow() {
        let slots = WindowSlots(snapshot: copilot(), modelSlotFallback: .auto).slots
        XCTAssertEqual(slots.map(\.kind), [.quota("premium_interactions"), .quota("chat"), .quota("completions")], "three at most, in the provider's order")
        XCTAssertEqual(slots.map { $0.window?.usedPct }, [38, 20, 4])
    }

    func testAMonthAloneIsOneSlotNotAnEmptySessionBesideIt() {
        let slots = WindowSlots(snapshot: codexFree(), modelSlotFallback: .auto).slots
        XCTAssertEqual(slots.map(\.kind), [.weekly])
        XCTAssertEqual(slots.first?.window?.duration, month)
        XCTAssertEqual(WindowSlots(snapshot: codexFree(), modelSlotFallback: .credits).slots.map(\.kind), [.weekly, .credits], "the third-slot fallback still applies")
    }

    func testGlanceOptionsFollowTheSnapshotAndTheMetricFallsBackToItsFirst() {
        XCTAssertEqual(UsageSnapshot.glanceOptions(for: copilot(), modelSlotFallback: .auto),
                       [.quota("premium_interactions"), .quota("chat"), .quota("completions"), .quota("extra")])
        XCTAssertEqual(UsageSnapshot.glanceOptions(for: codexFree(), modelSlotFallback: .auto), [.weekly])
        XCTAssertEqual(UsageSnapshot.glanceOptions(for: nil, modelSlotFallback: .auto), [.session, .weekly])
        XCTAssertEqual(UsageSnapshot.glanceMetric(.session, for: copilot(), modelSlotFallback: .auto), .quota("premium_interactions"))
        XCTAssertEqual(UsageSnapshot.glanceMetric(.session, for: codexFree(), modelSlotFallback: .auto), .weekly)
        XCTAssertEqual(UsageSnapshot.glanceMetric(.weekly, for: codexFree(), modelSlotFallback: .auto), .weekly)
        XCTAssertEqual(UsageSnapshot.glanceMetric(.session, for: nil, modelSlotFallback: .auto), .session)
    }

    func testTheMenuBarAndTheIslandReadTheFirstWindowOfAnAccountWithoutTheChosenOne() {
        let label = MenuBarLabelModel(
            snapshot: copilot(), displayMode: .used, style: .gaugeWithPercent, metric: .session, metrics: [.session, .weekly],
            modelSlotFallback: .auto, tintsAtDanger: false, showsCountdown: false, accountName: nil, now: now
        )
        XCTAssertEqual(label.text, "38%")
        XCTAssertTrue(label.accessibilityLabel.contains("Premium"), label.accessibilityLabel)

        let multi = MenuBarLabelModel(
            snapshot: codexFree(), displayMode: .used, style: .multi, metric: .session, metrics: [.session],
            modelSlotFallback: .auto, tintsAtDanger: false, showsCountdown: false, accountName: nil, now: now
        )
        XCTAssertEqual(multi.text, "W 12%")

        let island = NotchIslandModel(
            accounts: [.init(account: .init(accountID: "g1", providerID: "copilot", displayName: "Copilot", credentialStrategy: .managed), snapshot: copilot())],
            primaryID: "g1", displayMode: .used, resetStyle: .relative, modelSlotFallback: .auto, showCreditsAmount: false,
            usageColors: true, metrics: [.session, .weekly], glanceMetric: .session, layout: .bothSides, incident: nil, now: now
        )
        XCTAssertEqual(island.collapsed.left.map(\.label), ["Prem"])
        XCTAssertEqual(island.collapsed.left.first?.percent, "38%")
    }
}

final class WindowTitleTests: XCTestCase {
    func testTitlesFollowTheWindowsLength() {
        XCTAssertEqual(UsageWindow.Kind.session.title(duration: nil), "5-hour session")
        XCTAssertEqual(UsageWindow.Kind.session.title(duration: 5 * 3600), "5-hour session")
        XCTAssertEqual(UsageWindow.Kind.session.title(duration: 3 * 3600), "3-hour session")
        XCTAssertEqual(UsageWindow.Kind.weekly.title(duration: nil), "Weekly")
        XCTAssertEqual(UsageWindow.Kind.weekly.title(duration: 7 * 86400), "Weekly")
        XCTAssertEqual(UsageWindow.Kind.weekly.title(duration: 30 * 86400), "Monthly")
        XCTAssertEqual(UsageWindow.Kind.weekly.title(duration: 31 * 86400), "Monthly")
        XCTAssertEqual(UsageWindow.Kind.weekly.title(duration: 14 * 86400), "14-day window")
        XCTAssertEqual(UsageWindow.Kind.modelSpecific("Spark").title(duration: 7 * 86400), "Weekly · Spark")
        XCTAssertEqual(UsageWindow.Kind.modelSpecific("Spark").title(duration: 30 * 86400), "Monthly · Spark")
        XCTAssertEqual(UsageWindow.Kind.quota("premium_interactions").title(duration: 30 * 86400), "Premium requests")
        XCTAssertEqual(UsageWindow.Kind.quota("chat").displayName, "Chat")
        XCTAssertEqual(UsageWindow.Kind.quota("code_review").displayName, "Code review")
        XCTAssertEqual(UsageWindow.Kind.credits.title(duration: nil), "Credits")
    }

    func testShortTitlesAndTheWindowsOwn() {
        XCTAssertEqual(UsageWindow.Kind.weekly.shortTitle(duration: nil), "Week")
        XCTAssertEqual(UsageWindow.Kind.weekly.shortTitle(duration: 30 * 86400), "Month")
        XCTAssertEqual(UsageWindow.Kind.weekly.shortTitle(duration: 14 * 86400), "14d")
        XCTAssertEqual(UsageWindow.Kind.quota("premium_interactions").shortName, "Premium")
        let month = UsageWindow(kind: .weekly, usedPct: 1, duration: 30 * 86400)
        XCTAssertEqual(month.title, "Monthly")
        XCTAssertEqual(month.shortTitle, "Month")
        let snapshot = UsageSnapshot(providerID: "codex", windows: [month])
        XCTAssertEqual(snapshot.title(for: .weekly), "Monthly")
        XCTAssertEqual(snapshot.title(for: .session), "5-hour session", "the kind's own when the account has no such window")
    }

    func testTheMenuBarAbbreviatesQuotasApart() {
        XCTAssertEqual(MenuBarLabelModel.abbreviation(.quota("premium_interactions")), "P")
        XCTAssertEqual(MenuBarLabelModel.abbreviation(.quota("chat")), "Ch")
        XCTAssertEqual(MenuBarLabelModel.abbreviation(.quota("completions")), "Co")
        XCTAssertEqual(NotchIslandModel.label(for: .quota("completions"), duration: 30 * 86400, compact: true), "Comp")
        XCTAssertEqual(NotchIslandModel.label(for: .quota("completions"), duration: 30 * 86400, compact: false), "Completions")
        XCTAssertEqual(NotchIslandModel.label(for: .weekly, duration: 30 * 86400, compact: true), "30d")
    }
}
