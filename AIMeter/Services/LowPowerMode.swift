#if os(macOS)
import Foundation
import Observation

/// Whether the Mac is in Low Power Mode (System Settings, Battery), kept
/// current from `NSProcessInfoPowerStateDidChange`. Read by the session
/// pets, which stand still while it is on, the way they do under Reduce
/// Motion: their 8 Hz clock is the island's one steady redraw, and a
/// Mac saving battery has asked for exactly that to stop.
@MainActor
@Observable
final class LowPowerMode {
    static let shared = LowPowerMode()

    private(set) var isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                let on = ProcessInfo.processInfo.isLowPowerModeEnabled
                if LowPowerMode.shared.isOn != on { LowPowerMode.shared.isOn = on }
            }
        }
    }

    /// Whether the pets move: not under Reduce Motion, not in Low Power Mode.
    nonisolated static func petsAnimate(reduceMotion: Bool, lowPower: Bool) -> Bool {
        !reduceMotion && !lowPower
    }
}
#endif
