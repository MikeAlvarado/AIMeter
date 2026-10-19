import SwiftUI
#if os(iOS)
import UIKit
#endif

/// "Send feedback": a new issue in the project's repository, with the
/// version and the system already in its text. GitHub rather than mail,
/// so no address lives in the app and nothing is sent until the user
/// posts it there.
struct FeedbackSettings: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Card {
            Button {
                openURL(Self.issueURL())
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Send feedback")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        SectionFootnote(text: String(localized: "Opens a new issue in the project's GitHub repository with your AIMeter version and system already filled in. Nothing is sent until you post it there."))
    }

    static let newIssueURL = URL(string: "https://github.com/MikeAlvarado/AIMeter/issues/new")!

    /// The new issue's text: what every report needs and nobody thinks to
    /// say, left for the user to write under.
    static func issueURL(version: String = runningVersion, system: String = runningSystem) -> URL {
        var components = URLComponents(url: newIssueURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "body", value: "AIMeter \(version), \(system)\n\n")]
        return components.url ?? newIssueURL
    }

    /// "3.2.0 (1)".
    static var runningVersion: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// "iOS 27.0" / "iPadOS 27.0" / "macOS 27.0".
    static var runningSystem: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let number = v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
        #if os(iOS)
        return "\(UIDevice.current.systemName) \(number)"
        #else
        return "macOS \(number)"
        #endif
    }
}
