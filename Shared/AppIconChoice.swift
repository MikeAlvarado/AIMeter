import Foundation

/// The app's icon, picked in Settings: the notch island in four looks.
/// Sunset is the bundle's own icon (the primary one, what a new install
/// and the App Store show); the others are iOS alternate icons
/// (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`) and, on the Mac, a
/// Dock image. macOS has no way for an app to change its own icon short
/// of rewriting the bundle, which breaks its code signature, so there the
/// choice reaches the Dock and ⌘Tab while AIMeter runs and Finder keeps
/// Sunset (`AppChrome.applyAppIcon`). Every picture is drawn by
/// `Scripts/AppIcon/render.mjs`; the names here must match the ones it
/// writes, which `AppIconChoiceTests` checks against the bundle.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case sunset, ivory, night, pet

    var id: String { rawValue }

    /// iOS's name for the alternate icon; nil for the bundle's own.
    var alternateIconName: String? {
        switch self {
        case .sunset: nil
        case .ivory: "AppIcon-Ivory"
        case .night: "AppIcon-Night"
        case .pet: "AppIcon-Pet"
        }
    }

    /// The choice an alternate icon's name stands for; a name this build
    /// doesn't know (an icon a later version removed) is the bundle's own.
    init(alternateIconName: String?) {
        self = Self.allCases.first { $0.alternateIconName == alternateIconName } ?? .sunset
    }

    /// The picture Settings shows for it, full bleed (the view rounds it).
    var previewImageName: String { "AppIconPreview-\(assetSuffix)" }

    /// The Mac's Dock image for it, already in the Mac icon's shape; nil
    /// for the bundle's own, which the Dock shows by itself.
    var dockImageName: String? { self == .sunset ? nil : "AppIconDock-\(assetSuffix)" }

    private var assetSuffix: String {
        switch self {
        case .sunset: "Sunset"
        case .ivory: "Ivory"
        case .night: "Night"
        case .pet: "Pet"
        }
    }

    var label: String {
        switch self {
        case .sunset: String(localized: "Sunset", comment: "App icon choice: the notch island on a sunset sky, the default icon.")
        case .ivory: String(localized: "Ivory", comment: "App icon choice: the notch island on ivory.")
        case .night: String(localized: "Night", comment: "App icon choice: the notch island on a dark background.")
        case .pet: String(localized: "Pet", comment: "App icon choice: a session pet standing on the notch island.")
        }
    }
}
