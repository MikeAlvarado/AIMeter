import XCTest
@testable import AIMeter
import UsageKit

/// The account's pet in its Session Live Activity: which pet an account
/// gets, its mood from the figure and the provider's flag, and (iOS) the
/// attributes' pet across builds and the switch's storage.
final class LiveActivityPetTests: XCTestCase {
    func testAnAccountAlwaysGetsTheSamePet() {
        XCTAssertEqual(SessionPet(accountID: "claude"), SessionPet(index: SessionPet.naturalIndex(for: "claude")))
        XCTAssertEqual(SessionPet(accountID: "claude"), SessionPet(creature: .axolotl, palette: .pink, accessory: .none))
    }

    /// The bars' levels, so the pet gets nervous exactly where a bar turns
    /// yellow, and red where it turns red.
    func testTheMoodFollowsTheBarsLevels() {
        XCTAssertEqual(SessionPetMood(usedPct: 70.9, severity: nil), .calm, "a bar reading 70% is still terracotta")
        XCTAssertEqual(SessionPetMood(usedPct: 71, severity: nil), .nearLimit)
        XCTAssertEqual(SessionPetMood(usedPct: 85.9, severity: .normal), .nearLimit)
        XCTAssertEqual(SessionPetMood(usedPct: 86, severity: nil), .almostOut)
        XCTAssertEqual(SessionPetMood(usedPct: 10, severity: .warning), .nearLimit, "the provider's flag counts")
        XCTAssertEqual(SessionPetMood(usedPct: 10, severity: .critical), .almostOut)
        XCTAssertEqual(SessionPetMood(usedPct: 10, severity: .exceeded), .almostOut)
    }

    func testEachMoodHasItsPose() {
        XCTAssertEqual(SessionPetMood.calm.pose, .working)
        XCTAssertEqual(SessionPetMood.nearLimit.pose, .waiting)
        XCTAssertEqual(SessionPetMood.almostOut.pose, .waiting)
    }

    #if os(iOS)
    func testAnActivityFromAnOlderBuildHasNoPet() throws {
        let older = #"{"accountID":"claude","accountName":"Personal"}"#
        let attributes = try JSONDecoder().decode(SessionActivityAttributes.self, from: Data(older.utf8))
        XCTAssertNil(attributes.pet)
        XCTAssertNil(attributes.sessionPet)

        // By its parts' raw values, which a new creature never moves.
        let withPet = SessionActivityAttributes(
            accountID: "claude", accountName: "Personal", pet: .init(creature: 5, palette: 4, accessory: 1)
        )
        let decoded = try JSONDecoder().decode(SessionActivityAttributes.self, from: JSONEncoder().encode(withPet))
        XCTAssertEqual(decoded.pet, withPet.pet)
        XCTAssertEqual(decoded.sessionPet, SessionPet(creature: .fox, palette: .orange, accessory: .sunglasses))
    }

    func testThePetSwitchIsOffByDefaultAndGoesWithTheAccount() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let preferences = LiveActivityPreferences(accountID: "claude", defaults: scratch.defaults)
        XCTAssertNil(preferences.pet, "off by default")
        preferences.showsPet = true
        XCTAssertEqual(preferences.pet, .init(creature: 6, palette: 3, accessory: 0), "the account's own pet: a pink axolotl")
        preferences.enabled = true
        preferences.clear()
        XCTAssertFalse(preferences.enabled)
        XCTAssertFalse(preferences.showsPet)
        XCTAssertNil(preferences.pet)
    }
    #endif
}
