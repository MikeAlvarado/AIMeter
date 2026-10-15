import AppKit
import CoreImage
import ScreenCaptureKit

/// The notch island's panel, captured alone with ScreenCaptureKit at its
/// display's own scale, its transparent pixels left transparent, so the
/// recording shows nothing of the real desktop. `latest` is the newest
/// complete frame, always the whole panel: the capture is of the panel's
/// rectangle on its display with only that window in it. A capture of
/// the window by itself crops it to what is drawn and puts that in the
/// frame's top left corner, so the island lost its place (measured on a
/// MacBook: the collapsed notch came out 260 pt left of where it is).
final class PanelCapture: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var newest: CGImage?
    private var stream: SCStream?
    private let context = CIContext()
    private(set) var pointSize: CGSize = .zero
    private(set) var scale: CGFloat = 1
    /// From the panel's left edge to what the island centres on: the
    /// notch, or the screen's middle on a screen without one.
    private(set) var anchorOffset: CGFloat = 0

    var latest: CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return newest
    }

    /// The panel: AIMeter's window at the island's level (`mainMenu + 3`).
    func start(bundleID: String) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: {
            $0.owningApplication?.bundleIdentifier == bundleID && $0.windowLayer == Int(CGWindowLevelForKey(.mainMenuWindow)) + 3
        }), let display = content.displays.first(where: {
            $0.frame.contains(CGPoint(x: window.frame.midX, y: window.frame.minY))
        }) else {
            throw CaptureError.noPanel
        }
        let filter = SCContentFilter(display: display, including: [window])
        scale = CGFloat(SCShareableContent.info(for: filter).pointPixelScale)
        pointSize = window.frame.size
        anchorOffset = await MainActor.run { Self.anchorX(for: window.frame) } - window.frame.minX
        let config = SCStreamConfiguration()
        // The panel's rectangle, in its display's points.
        config.sourceRect = window.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.backgroundColor = CGColor.clear
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "island.capture"))
        try await stream.startCapture()
        self.stream = stream
    }

    /// The notch's centre on the panel's screen, or the screen's middle.
    /// Global x is the same in the window list's and AppKit's spaces.
    @MainActor
    private static func anchorX(for frame: CGRect) -> CGFloat {
        guard let screen = NSScreen.screens.first(where: { $0.frame.minX <= frame.midX && frame.midX < $0.frame.maxX }) else { return frame.midX }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return (left.maxX + right.minX) / 2
        }
        return screen.frame.midX
    }

    func stop() async {
        try? await stream?.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = sampleBuffer.imageBuffer,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let frame = context.createCGImage(image, from: image.extent) else { return }
        lock.lock()
        newest = frame
        lock.unlock()
    }

    enum CaptureError: Error, CustomStringConvertible {
        case noPanel
        var description: String { "No notch island panel on screen: is AIMeter running with the island on?" }
    }
}
