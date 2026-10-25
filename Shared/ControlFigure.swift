import Foundation
import UsageKit

/// What iOS 18's control (`UsageControl`, Control Center and the Lock
/// Screen) shows for an account: its nickname, the window the Lock
/// Screen gauge reads (`glanceMetric`, falling back like it does) with
/// its short title and percentage as Settings displays it, and how full
/// the gauge glyph is. Pure, so the tests reach it.
struct ControlFigure: Equatable {
    let accountID: String
    /// The account's nickname.
    let title: String
    /// "Session 42%", or "--" before the first fetch.
    let figure: String
    /// 0 to 1, the gauge glyph's fill.
    let fraction: Double

    init(accountID: String, name: String, snapshot: UsageSnapshot?, prefs: Preferences) {
        self.accountID = accountID
        title = name
        let kind = UsageSnapshot.glanceMetric(prefs.glanceMetric, for: snapshot, modelSlotFallback: prefs.modelSlotFallback)
        guard let window = snapshot?.window(for: kind) else {
            figure = "--"
            fraction = 0
            return
        }
        let pct = min(max(window.displayedPct(prefs.displayMode), 0), 100)
        figure = "\(window.shortTitle) \(Int(pct))%"
        fraction = pct / 100
    }
}
