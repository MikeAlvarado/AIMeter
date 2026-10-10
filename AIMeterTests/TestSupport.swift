import Foundation
import XCTest
import UsageKit
@testable import AIMeter

/// A throwaway `UserDefaults` suite per test, wiped on teardown, so tests
/// never touch the real App Group container the host app opens.
final class ScratchDefaults {
    let suiteName = "aimeter.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func wipe() {
        defaults.removePersistentDomain(forName: suiteName)
        #if os(macOS)
        // Emptying the suite leaves its plist behind on the Mac — one
        // 42-byte file per test in ~/Library/Preferences, over a thousand
        // after a day of runs. The test host is unsandboxed, so that is
        // where it lives.
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: file)
        #endif
    }
}

extension UsageWindow {
    static func make(_ kind: Kind, used: Double, resetsIn: TimeInterval? = nil, now: Date = Date()) -> UsageWindow {
        UsageWindow(kind: kind, usedPct: used, resetsAt: resetsIn.map { now.addingTimeInterval($0) })
    }
}

extension UsageSnapshot {
    static func make(windows: [UsageWindow], spend: SpendStatus? = nil) -> UsageSnapshot {
        UsageSnapshot(providerID: ProviderCatalog.defaultProviderID, planName: "pro", windows: windows, spend: spend)
    }
}

extension ConnectedAccount {
    static func managed(_ id: String, name: String) -> ConnectedAccount {
        ConnectedAccount(accountID: id, providerID: ProviderCatalog.defaultProviderID, displayName: name, credentialStrategy: .managed)
    }
}
