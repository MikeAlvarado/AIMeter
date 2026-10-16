#if os(macOS)
import AppKit
import CryptoKit
import Foundation
import Security

/// Everything the updater does to files: download the zip, prove it is
/// the release (its SHA-256 against the one GitHub states, then the app's
/// signature: Apple-anchored, this bundle ID, the same team as the
/// running app), unpack it, and finally swap it in place of the running
/// copy and relaunch. Nothing is installed that fails a check; the
/// download folder is the only thing written until the user restarts.
nonisolated enum UpdateInstaller {
    /// `~/Library/Caches/com.mikealvarado.aimeter/Updates/`.
    static var updatesFolder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.mikealvarado.aimeter", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }

    static let appName = "AIMeter.app"

    // MARK: Prepare

    /// Downloads, checks and unpacks `offer`: the new app, ready to swap in.
    /// Off the main actor (a nonisolated `async` function runs on its
    /// caller's): hashing the zip and checking every nested signature
    /// take long enough to stall the island and the menu bar.
    @concurrent
    static func prepare(_ offer: UpdateFeed.Offer, session: URLSession = .shared) async throws -> URL {
        let folder = updatesFolder.appendingPathComponent(offer.version.description, isDirectory: true)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: folder)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let (downloaded, response) = try await session.download(from: offer.download)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.download(status: http.statusCode)
        }
        let zip = folder.appendingPathComponent(UpdateFeed.assetName)
        try fileManager.moveItem(at: downloaded, to: zip)
        if let expected = offer.sha256, try sha256(of: zip) != expected.lowercased() {
            throw UpdateError.digest
        }

        try await unzip(zip, into: folder)
        try? fileManager.removeItem(at: zip)
        let app = folder.appendingPathComponent(appName, isDirectory: true)
        guard fileManager.fileExists(atPath: app.path) else { throw UpdateError.unpack }
        guard let team = runningTeam, let bundleID = Bundle.main.bundleIdentifier,
              isTrusted(app, team: team, bundleID: bundleID) else { throw UpdateError.untrusted }
        guard let bundle = Bundle(url: app), AppVersion.version(of: bundle) == offer.version else {
            throw UpdateError.wrongVersion
        }
        return app
    }

    static func sha256(of file: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    }

    /// `ditto`, which keeps the signature's extended attributes intact.
    private static func unzip(_ zip: URL, into folder: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, folder.path]
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else { throw UpdateError.unpack }
    }

    // MARK: Trust

    /// The team that signed the running app; nil for an unsigned build,
    /// which therefore never installs anything.
    static var runningTeam: String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return nil }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Valid, Apple-anchored, this bundle ID, signed by `team`, nested
    /// code (the widget) included.
    static func isTrusted(_ app: URL, team: String, bundleID: String) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let text = "anchor apple generic and identifier \"\(bundleID)\" and certificate leaf[subject.OU] = \"\(team)\""
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else {
            return false
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    // MARK: Install

    /// Whether the running copy can be replaced where it is: not run from
    /// a quarantined download (App Translocation's read-only mirror), and
    /// in a folder this user can write to (an app dragged to
    /// /Applications by its owner is).
    static func canReplace(_ app: URL) -> Bool {
        !isTranslocated(app.path)
            && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
            && FileManager.default.isWritableFile(atPath: app.path)
    }

    static func isTranslocated(_ path: String) -> Bool {
        path.contains("/AppTranslocation/")
    }

    /// The script that does the swap once this process is gone: wait for
    /// it to exit, set the running copy aside, move the new one into its
    /// place (putting the old one back if that fails, over whatever part
    /// of the new one a move across volumes left: `mv` onto a folder that
    /// exists would put the old copy inside it), delete the previous
    /// version and the download, and open the result.
    static func installScript(processID: Int32, app: URL, update: URL, downloads: URL) -> String {
        let quoted = { (url: URL) in "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return """
        #!/bin/sh
        while kill -0 \(processID) 2>/dev/null; do sleep 0.2; done
        app=\(quoted(app))
        previous="$app.previous"
        rm -rf "$previous"
        if mv "$app" "$previous"; then
          if mv \(quoted(update)) "$app"; then
            rm -rf "$previous"
          else
            rm -rf "$app"
            mv "$previous" "$app"
          fi
        fi
        rm -rf \(quoted(downloads))
        open "$app"
        """
    }

    /// Hands the swap to `installScript`, which outlives this process,
    /// then quits so it can run.
    @MainActor
    static func installAndRelaunch(update: URL, replacing app: URL = Bundle.main.bundleURL) throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("aimeter-update-\(UUID().uuidString).sh")
        let text = installScript(
            processID: ProcessInfo.processInfo.processIdentifier,
            app: app,
            update: update,
            downloads: updatesFolder
        )
        try text.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        try process.run()
        AppChrome.closeUpdateWindow()
        NSApp.terminate(nil)
    }

    /// What a past update left behind: downloads other than `keeping`
    /// (the one waiting for a restart), and a previous version the swap
    /// could not delete.
    static func cleanUp(keeping: URL?, app: URL = Bundle.main.bundleURL) {
        let fileManager = FileManager.default
        let kept = keeping?.deletingLastPathComponent().standardizedFileURL
        for item in (try? fileManager.contentsOfDirectory(at: updatesFolder, includingPropertiesForKeys: nil)) ?? []
        where item.standardizedFileURL != kept {
            try? fileManager.removeItem(at: item)
        }
        let previous = URL(fileURLWithPath: app.path + ".previous")
        if fileManager.fileExists(atPath: previous.path) {
            try? fileManager.removeItem(at: previous)
        }
    }
}
#endif
