import XCTest
@testable import AIMeter
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The app icon picked in Settings: Sunset is the bundle's own, every
/// other look has its alternate (iOS) or Dock image (Mac) in the bundle
/// under the name `AppIconChoice` gives it, and the Mac's preference
/// falls back to Sunset.
final class AppIconChoiceTests: XCTestCase {
    func testSunsetIsTheBundlesOwnIcon() {
        XCTAssertNil(AppIconChoice.sunset.alternateIconName)
        XCTAssertNil(AppIconChoice.sunset.dockImageName)
        XCTAssertEqual(AppIconChoice(alternateIconName: nil), .sunset)
    }

    func testEveryChoiceRoundTripsThroughItsAlternateName() {
        for choice in AppIconChoice.allCases {
            XCTAssertEqual(AppIconChoice(alternateIconName: choice.alternateIconName), choice)
        }
        XCTAssertEqual(AppIconChoice(alternateIconName: "AppIcon-Gone"), .sunset, "an icon a later build removed reads as the bundle's own")
        XCTAssertEqual(Set(AppIconChoice.allCases.compactMap(\.alternateIconName)).count, AppIconChoice.allCases.count - 1)
    }

    func testEveryPreviewIsInTheBundle() {
        for choice in AppIconChoice.allCases {
            #if os(iOS)
            XCTAssertNotNil(UIImage(named: choice.previewImageName), choice.rawValue)
            #else
            XCTAssertNotNil(NSImage(named: choice.previewImageName), choice.rawValue)
            #endif
        }
    }

    #if os(iOS)
    func testEveryAlternateIsDeclaredToTheSystem() throws {
        let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any], "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES")
        for choice in AppIconChoice.allCases {
            guard let name = choice.alternateIconName else { continue }
            XCTAssertNotNil(alternates[name], name)
        }
    }
    #else
    func testEveryDockImageIsInTheBundle() {
        for choice in AppIconChoice.allCases {
            guard let name = choice.dockImageName else { continue }
            let image = NSImage(named: name)
            XCTAssertNotNil(image, name)
            XCTAssertEqual(image?.size.width, image?.size.height, "\(name) is square, as a Dock tile is")
        }
    }

    func testTheMacPreferenceDefaultsToSunsetAndRoundTrips() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        XCTAssertEqual(Preferences.load(from: scratch.defaults).appIcon, .sunset)

        let model = PreferencesModel(defaults: scratch.defaults)
        model.appIcon = .pet
        XCTAssertEqual(Preferences.load(from: scratch.defaults).appIcon, .pet)

        scratch.defaults.set("aurora", forKey: Preferences.Keys.appIcon)
        XCTAssertEqual(Preferences.load(from: scratch.defaults).appIcon, .sunset, "an unknown value falls back to the bundle's own")
    }
    #endif
}
