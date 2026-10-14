import Foundation
import UsageKit

/// Each release's notes, shown as a short "What's new" sheet: on iOS once
/// after the App Store installs a new version, and on the Mac in the
/// update notice before installing, read from the downloaded app's own
/// copy of `WhatsNew.json`. That is why the notes are a JSON resource
/// rather than strings in the catalog: the notice has to show the next
/// version's notes, which only the next version carries. Every item is
/// written in all eight of the app's languages (`WhatsNewTests` holds
/// that, and `Scripts/release-mac.sh` refuses a version without its
/// entry).
nonisolated struct WhatsNew: Decodable, Equatable, Sendable {
    struct Release: Decodable, Equatable, Identifiable, Sendable {
        let version: String
        let items: [Item]
        var id: String { version }
    }

    struct Item: Decodable, Equatable, Identifiable, Sendable {
        /// An SF Symbol.
        let symbol: String
        /// Language code (`WhatsNew.languages`) to text.
        let title: [String: String]
        let detail: [String: String]
        /// "iOS" and/or "macOS"; absent, the item is for both.
        let platforms: [String]?
        var id: String { symbol + (title["en"] ?? "") }
    }

    /// Newest first.
    let releases: [Release]

    /// The app's languages, as the notes key them.
    static let languages = ["en", "es", "de", "fr", "ja", "ko", "pt-BR", "zh-Hans"]
    static let resourceName = "WhatsNew"

    #if os(macOS)
    static let platform = "macOS"
    #else
    static let platform = "iOS"
    #endif

    /// The notes `bundle` carries: this app's, or a downloaded update's.
    static func load(from bundle: Bundle = .main) -> WhatsNew? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WhatsNew.self, from: data)
    }

    /// `version`'s notes, only the items for this platform; nil when it
    /// has none.
    func release(_ version: AppVersion) -> Release? {
        releases.first { AppVersion($0.version) == version }.flatMap(Self.forThisPlatform)
    }

    /// What a user moving from `lastSeen` to `current` hasn't read: every
    /// release in between, newest first, as one list under `current`.
    func notes(after lastSeen: AppVersion, upTo current: AppVersion) -> Release? {
        let items = releases
            .filter { AppVersion($0.version).map { $0 > lastSeen && $0 <= current } ?? false }
            .compactMap(Self.forThisPlatform)
            .flatMap(\.items)
        return items.isEmpty ? nil : Release(version: current.description, items: items)
    }

    private static func forThisPlatform(_ release: Release) -> Release? {
        let items = release.items.filter { $0.platforms?.contains(platform) ?? true }
        return items.isEmpty ? nil : Release(version: release.version, items: items)
    }

    /// The notes due at launch, if any. `lastSeen` is nil until this
    /// feature has run once: a fresh install has nothing to catch up on,
    /// while an install that already has accounts came from an older
    /// version and gets this version's notes.
    static func pending(
        notes: WhatsNew?,
        current: AppVersion,
        lastSeen: AppVersion?,
        hasPriorInstall: Bool
    ) -> Release? {
        guard let notes else { return nil }
        guard let lastSeen else {
            return hasPriorInstall ? notes.release(current) : nil
        }
        return notes.notes(after: lastSeen, upTo: current)
    }

    /// `table`'s text in `language` (the app's own, from
    /// `Bundle.main.preferredLocalizations`), or its language without the
    /// region, or English.
    static func text(_ table: [String: String], language: String) -> String {
        if let exact = table[language] { return exact }
        let base = String(language.prefix { $0 != "-" })
        if let match = table.first(where: { $0.key == base || $0.key.hasPrefix(base + "-") }) {
            return match.value
        }
        return table["en"] ?? ""
    }

    static var appLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    // MARK: Seen

    /// The newest version whose notes this install has shown (or that it
    /// was installed at), in the App Group like every other preference.
    @MainActor
    static var lastSeen: AppVersion? {
        get { Preferences.groupDefaults.string(forKey: seenKey).flatMap(AppVersion.init) }
        set { Preferences.groupDefaults.set(newValue?.description, forKey: seenKey) }
    }

    static let seenKey = "pref.whatsNewSeenVersion"

    /// The release to show at launch, read once; records the current
    /// version straight away when there is nothing to show.
    @MainActor
    static func dueAtLaunch() -> Release? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let current = AppVersion.current else { return nil }
        let prior = !(AccountRegistryStore(suiteName: AppConfig.appGroupID)?.accounts().isEmpty ?? true)
        let due = pending(notes: load(), current: current, lastSeen: lastSeen, hasPriorInstall: prior)
        if due == nil, (lastSeen ?? AppVersion("0")!) < current {
            lastSeen = current
        }
        return due
    }
}
