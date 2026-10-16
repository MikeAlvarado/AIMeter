#if os(macOS)
import AppKit
import ApplicationServices

/// The menu bar's own items, so the collapsed island's session name never
/// covers them (`NotchIslandClearance`), beside a real notch or in the
/// drawn notch's or the pill's row. The status items on the right
/// come from the public window list where each is a window of its own
/// (macOS 26 and earlier, no permission), and from the Accessibility API
/// on macOS 27, where `MenuBarAgent` draws every status item and the
/// window list carries none of them (measured: only the agent's bar, at
/// level 24, and one zero-size window per app). The open app's menu
/// titles on the left come from the Accessibility API too. Both of those
/// reads need "Avoid covering the menu bar" on and the permission, and
/// run on their own queue: the first read of an app takes tens of
/// milliseconds (1.5 s for every app running here, measured), later ones
/// a few milliseconds for all of them, and an app that doesn't answer
/// would otherwise hold the main thread to the timeout. Nothing is ever
/// read but those frames.
extension NotchIslandController {
    /// Where the Accessibility reads run, one at a time.
    private static let clearanceQueue = DispatchQueue(label: "com.mikealvarado.aimeter.notch-clearance", qos: .utility)
    /// How often the watch reads again the apps found with status items,
    /// while the Accessibility path runs: an item that changes width (a
    /// temperature, a battery's percentage) moves every item left of it,
    /// with nothing to announce it.
    private static let clearanceWatchInterval: Duration = .seconds(20)

    /// Measures again and publishes how wide each wing may grow: on every
    /// relocation (screen, Space, wake, a preference write) and, through
    /// `scheduleClearanceChecks`, after an app switch, launch or quit.
    /// `everyApp` asks every app that can have a status item; the watch's
    /// ticks only ask the ones found with one last time.
    func refreshClearance(everyApp: Bool = true) {
        // Only a session's name beside the notch reads the clearance: with
        // no name to show (or the island stopped, and a delayed check from
        // before still landing), nothing is measured.
        guard isRunning, let screen, let prefs, prefs.claudeSessionsEnabled, prefs.claudeSessionsShowsName else {
            stopClearanceWatch()
            if state.availableWing != nil { state.availableWing = nil }
            return
        }
        // The notch, or the centre line a drawn row is centred on.
        let notch = NotchIslandClearance.anchor(mode: state.mode, screen: screen)
        let ear = NotchIslandClearance.ear(mode: state.mode, barHeight: state.barHeight)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let menuBarTop = primaryTop - screen.frame.maxY
        let menuBarHeight = screen.safeTop
        let fromWindows = NotchIslandClearance.statusItemsMinX(
            Self.onScreenWindows(), notch: notch, menuBarTop: menuBarTop, menuBarHeight: menuBarHeight
        )
        // Without the permission there is nothing to watch: an app switch
        // measures again, and so does a change to the Accessibility list
        // (`com.apple.accessibility.api`, observed in `observe()`), so the
        // island notices a permission given in System Settings at once.
        guard prefs.claudeSessionsAvoidsMenus, AccessibilityAccess.check(prefs: prefs) == .granted else {
            stopClearanceWatch()
            publishClearance(notch: notch, ear: ear, menusMaxX: nil, statusItemsMinX: fromWindows)
            return
        }
        startClearanceWatch()
        clearanceGeneration += 1
        let generation = clearanceGeneration
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // An app the system keeps from having any UI has no status item.
        let apps = everyApp
            ? NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }.map(\.processIdentifier)
            : statusItemApps
        let deliver: @MainActor (_ menus: [CGRect], _ items: [(pid: pid_t, frames: [CGRect])]) -> Void = { [weak self] menus, items in
            guard let self else { return }
            // The queue is serial, so a survey of every app is never older
            // than the list it replaces, even when a later measurement takes
            // over the publishing.
            if everyApp {
                self.statusItemApps = items.filter { !$0.frames.isEmpty }.map(\.pid)
            }
            guard self.clearanceGeneration == generation else { return }
            let fromAccessibility = NotchIslandClearance.statusItemsMinX(
                items: items.flatMap(\.frames), notch: notch, menuBarTop: menuBarTop, menuBarHeight: menuBarHeight
            )
            self.publishClearance(
                notch: notch,
                ear: ear,
                menusMaxX: NotchIslandClearance.menusMaxX(menus, notch: notch),
                statusItemsMinX: [fromWindows, fromAccessibility].compactMap { $0 }.min()
            )
        }
        Self.clearanceQueue.async {
            Self.limitAccessibilityWaits()
            let menus = frontmost.map(Self.menuFrames(of:)) ?? []
            let items = apps.map { (pid: $0, frames: Self.statusItemFrames(of: $0)) }
            Task { @MainActor in deliver(menus, items) }
        }
    }

    private func publishClearance(notch: CGRect, ear: CGFloat, menusMaxX: CGFloat?, statusItemsMinX: CGFloat?) {
        let wing = NotchIslandClearance.availableWing(
            notch: notch, menusMaxX: menusMaxX, statusItemsMinX: statusItemsMinX, ear: ear
        )
        if state.availableWing != wing { state.availableWing = wing }
    }

    /// Now and again after each delay: after an app switch the new menus
    /// settle within a moment, while a launched app's status item can take
    /// a few seconds to appear.
    func scheduleClearanceChecks(after delays: [Duration] = [.milliseconds(400)]) {
        refreshClearance()
        for delay in delays {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                self?.refreshClearance()
            }
        }
    }

    private func startClearanceWatch() {
        guard clearanceWatchTask == nil else { return }
        clearanceWatchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.clearanceWatchInterval)
                guard !Task.isCancelled else { return }
                self?.refreshClearance(everyApp: false)
            }
        }
    }

    func stopClearanceWatch() {
        clearanceWatchTask?.cancel()
        clearanceWatchTask = nil
    }

    /// Every on-screen window's frame and level, no names (those would
    /// need the Screen Recording permission).
    private static func onScreenWindows() -> [NotchIslandClearance.Window] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return NotchIslandClearance.Window(frame: frame, layer: layer)
        }
    }

    /// The frames of an app's menu titles, as the Accessibility API
    /// reports them; empty without an answer within a quarter of a second.
    nonisolated private static func menuFrames(of pid: pid_t) -> [CGRect] {
        items(of: kAXMenuBarAttribute, pid: pid)
    }

    /// The frames of an app's status items (its "extras" menu bar).
    nonisolated private static func statusItemFrames(of pid: pid_t) -> [CGRect] {
        items(of: kAXExtrasMenuBarAttribute, pid: pid)
    }

    /// A quarter of a second for every Accessibility read this app makes,
    /// the menu bar's items included: a timeout set on an app's element
    /// alone left the reads of its children to the default of several
    /// seconds, and one app that doesn't answer held the queue that long.
    nonisolated private static func limitAccessibilityWaits() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
    }

    nonisolated private static func items(of bar: String, pid: pid_t) -> [CGRect] {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.25)
        guard let bar = attribute(bar, of: element),
              CFGetTypeID(bar) == AXUIElementGetTypeID(),
              let children = attribute(kAXChildrenAttribute, of: bar as! AXUIElement) as? [AXUIElement] else { return [] }
        return children.compactMap { item in
            guard let position = attribute(kAXPositionAttribute, of: item),
                  let size = attribute(kAXSizeAttribute, of: item),
                  CFGetTypeID(position) == AXValueGetTypeID(),
                  CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
            var origin = CGPoint.zero
            var extent = CGSize.zero
            AXValueGetValue(position as! AXValue, .cgPoint, &origin)
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
            return CGRect(origin: origin, size: extent)
        }
    }

    nonisolated private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
#endif
