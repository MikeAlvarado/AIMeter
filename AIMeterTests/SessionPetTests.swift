import XCTest
@testable import AIMeter

/// The session pets: every combination reachable and distinct, a session's
/// pet stable across launches, no two pets alike on screen, and every
/// creature, accessory and pose inside its canvas on every tick (the "!"
/// is drawn beside the pet, so nothing leaves the island's bar).
final class SessionPetTests: XCTestCase {
    func testEveryCombinationIsReachableAndDistinct() {
        XCTAssertEqual(SessionPet.count, 216)
        let pets = (0..<SessionPet.count).map { SessionPet(index: $0) }
        XCTAssertEqual(Set(pets).count, SessionPet.count)
        for index in 0..<SessionPet.count {
            XCTAssertEqual(SessionPet(index: index).index, index)
        }
        XCTAssertEqual(SessionPet(index: -1), SessionPet(index: SessionPet.count - 1), "wraps either way")
    }

    func testAnIdAlwaysPointsAtTheSamePet() {
        // FNV-1a, so the same on every launch (Swift's hashValue isn't).
        XCTAssertEqual(SessionPet.naturalIndex(for: "6b1f-session"), 159)
        XCTAssertEqual(SessionPet.naturalIndex(for: "4ecb0e0b-fc32-41ac-9678-01cf9aa00413"), 58)
        XCTAssertEqual(SessionPet.naturalIndex(for: "a"), 124)
    }

    func testNoTwoPetsAlikeWhateverTheOrder() {
        let ids = (0..<40).map { "session-\($0)" }
        let dealt = SessionPet.deal(ids)
        XCTAssertEqual(dealt.count, ids.count)
        XCTAssertEqual(Set(dealt.values).count, ids.count)
        XCTAssertEqual(SessionPet.deal(ids.reversed()), dealt, "the deal doesn't depend on the order shown")
        // "s51" and "s60" point at the same pet: the one sorted second takes the next.
        XCTAssertEqual(SessionPet.naturalIndex(for: "s51"), SessionPet.naturalIndex(for: "s60"))
        let pair = SessionPet.deal(["s60", "s51"])
        XCTAssertEqual(pair["s51"]?.index, 156)
        XCTAssertEqual(pair["s60"]?.index, 157)
    }

    func testEveryPetStaysInsideItsCanvas() {
        for index in 0..<SessionPet.count {
            let pet = SessionPet(index: index)
            for pose in [SessionPet.Pose.working, .waiting, .asleep] {
                for tick in 0..<16 {
                    for pixel in pet.pixels(pose: pose, tick: tick) {
                        XCTAssertTrue((0..<SessionPet.canvasWidth).contains(pixel.x) && (0..<SessionPet.canvasHeight).contains(pixel.y),
                                      "\(pet) \(pose) tick \(tick): \(pixel)")
                    }
                }
            }
        }
    }

    func testThePosesMove() {
        let pet = SessionPet(creature: .cat, palette: .blue, accessory: .none)
        XCTAssertNotEqual(pet.pixels(pose: .working, tick: 0), pet.pixels(pose: .working, tick: 2), "a step")
        XCTAssertNotEqual(pet.pixels(pose: .waiting, tick: 1), pet.pixels(pose: .waiting, tick: 3), "a shake")
        let zzz = SessionPet.Pixel(x: 12, y: 1, tone: .white)
        XCTAssertTrue(pet.pixels(pose: .asleep, tick: 0).contains(zzz), "the z, on")
        XCTAssertFalse(pet.pixels(pose: .asleep, tick: 12).contains(zzz), "and off")
        XCTAssertFalse(pet.pixels(pose: .working, tick: 0).contains(zzz))
    }

    func testThePixelLandsOnWholeDevicePixels() {
        XCTAssertEqual(SessionPet.pixelSize(fitting: 28, displayScale: 2), 2)
        XCTAssertEqual(SessionPet.pixelSize(fitting: 24, displayScale: 2), 1.5)
        XCTAssertEqual(SessionPet.pixelSize(fitting: 24, displayScale: 1), 1)
        XCTAssertEqual(SessionPet.pixelSize(fitting: 4, displayScale: 2), 0.5, "never smaller than a device pixel")
        XCTAssertEqual(SessionPet.pixelSize(beside: 32, displayScale: 2), 1.5, "a MacBook's notch: air above and below the pet")
        XCTAssertEqual(SessionPet.pixelSize(beside: 24, displayScale: 2), 1)
        XCTAssertEqual(SessionPet.pixelSize(beside: 30, displayScale: 1), 1)
    }
}
