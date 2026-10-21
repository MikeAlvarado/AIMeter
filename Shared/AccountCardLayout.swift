import Foundation
import UsageKit

/// How an account card is composed (4.0): one window as its protagonist,
/// drawn large, and the rest of `WindowSlots` as compact one-line rows
/// under it, in their own order. The protagonist is the window closest to
/// its limit, by the same measure the urgency order uses for whole
/// accounts (`AccountOrder.urgency`): its used percentage, a window the
/// provider flags critical or exceeded counting as full. Ties keep the
/// slots' order, so on a quiet day the session leads, as it always has.
/// Before the first fetch (or with no window at all) the first slot leads,
/// as a placeholder.
struct AccountCardLayout {
    typealias Slot = (kind: UsageWindow.Kind, window: UsageWindow?)

    let hero: Slot
    let others: [Slot]
    /// Where the protagonist sat in `WindowSlots`, for callers that need
    /// the grouped reset rule over the original order.
    let heroIndex: Int

    init(slots: [Slot]) {
        let index = Self.heroIndex(in: slots)
        heroIndex = index
        if slots.indices.contains(index) {
            hero = slots[index]
            var rest = slots
            rest.remove(at: index)
            others = rest
        } else {
            hero = (.session, nil)
            others = []
        }
    }

    init(snapshot: UsageSnapshot?, modelSlotFallback: ModelSlotFallback) {
        self.init(slots: WindowSlots(snapshot: snapshot, modelSlotFallback: modelSlotFallback).slots)
    }

    static func heroIndex(in slots: [Slot]) -> Int {
        var best: (index: Int, urgency: Double)?
        for (index, slot) in slots.enumerated() {
            guard let window = slot.window else { continue }
            let urgency = urgency(of: window)
            if best == nil || urgency > best!.urgency {
                best = (index, urgency)
            }
        }
        return best?.index ?? 0
    }

    static func urgency(of window: UsageWindow) -> Double {
        window.severity == .critical || window.severity == .exceeded ? max(window.usedPct, 100) : window.usedPct
    }
}
