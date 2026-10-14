import Foundation

/// A Claude Code session's pixel pet in the notch island (see "Claude Code
/// sessions" in the repo-root CLAUDE.md): one of six creatures, in one of
/// six colors, with one of six accessories (none among them), 216
/// combinations in all. A session's pet comes from its id, so it keeps it
/// as long as it is shown, and no two sessions on screen share one
/// (`deal`). Pure: the pixels are computed here (`SessionPet+Sprites.swift`)
/// and only painted by `PixelPetView`, which is what lets the tests check
/// every creature, accessory and pose against the canvas.
struct SessionPet: Hashable, Sendable {
    enum Creature: Int, CaseIterable, Sendable { case drop, ghost, cat, bunny, frog, fox }
    /// No yellow and no red: in the island those mean a permission prompt
    /// and a limit.
    enum Palette: Int, CaseIterable, Sendable { case blue, purple, green, pink, orange, lime }
    enum Accessory: Int, CaseIterable, Sendable { case none, sunglasses, topHat, beanie, bow, headphones }
    /// Walking in place while the session works, shaking while it waits for
    /// a permission prompt, asleep once its turn is done.
    enum Pose: Sendable { case working, waiting, asleep }

    let creature: Creature
    let palette: Palette
    let accessory: Accessory

    static let count = Creature.allCases.count * Palette.allCases.count * Accessory.allCases.count

    init(creature: Creature, palette: Palette, accessory: Accessory) {
        self.creature = creature
        self.palette = palette
        self.accessory = accessory
    }

    /// The pet at `index` in 0..<count (wrapping around either way).
    init(index: Int) {
        let creatures = Creature.allCases.count, palettes = Palette.allCases.count
        let value = ((index % Self.count) + Self.count) % Self.count
        creature = Creature(rawValue: value % creatures) ?? .drop
        palette = Palette(rawValue: (value / creatures) % palettes) ?? .blue
        accessory = Accessory(rawValue: value / (creatures * palettes)) ?? .none
    }

    var index: Int {
        let creatures = Creature.allCases.count, palettes = Palette.allCases.count
        return creature.rawValue + creatures * palette.rawValue + creatures * palettes * accessory.rawValue
    }

    /// The combination an id points at: FNV-1a over its UTF-8, the same on
    /// every launch (Swift's `hashValue` is seeded per process).
    static func naturalIndex(for id: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(count))
    }

    /// One pet per id, no two alike. The ids are dealt in sorted order, so
    /// the deal doesn't depend on the order they are shown in: each takes
    /// the combination it points at, or the next one free.
    static func deal(_ ids: [String]) -> [String: SessionPet] {
        var taken = Set<Int>()
        var pets: [String: SessionPet] = [:]
        for id in Set(ids).sorted() {
            var index = naturalIndex(for: id)
            while taken.contains(index) {
                index = (index + 1) % count
            }
            taken.insert(index)
            pets[id] = SessionPet(index: index)
        }
        return pets
    }

    // MARK: Clock

    /// The island's animation clock: eight ticks a second, shared by every
    /// pet so they step together.
    static let tickInterval: TimeInterval = 0.125
    static let epoch = Date(timeIntervalSinceReferenceDate: 0)

    static func tick(at date: Date) -> Int {
        Int((date.timeIntervalSince(epoch) / tickInterval).rounded(.down))
    }

    /// The largest sprite pixel that fits the canvas in `height` points
    /// and lands on whole device pixels, so the pet stays crisp.
    static func pixelSize(fitting height: CGFloat, displayScale: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        let fitted = (height / CGFloat(canvasHeight) * scale).rounded(.down) / scale
        return max(1 / scale, fitted)
    }

    /// The pixel of a pet beside the notch: its canvas in two thirds of
    /// the bar, so the pet keeps air above and below it (1.5 pt on a
    /// MacBook's 32 pt notch, the body half the bar's height, as on the
    /// mockup the pets were approved on).
    static func pixelSize(beside barHeight: CGFloat, displayScale: CGFloat) -> CGFloat {
        pixelSize(fitting: barHeight * 2 / 3, displayScale: displayScale)
    }
}
