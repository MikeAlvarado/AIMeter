import AppKit
import AVFoundation

/// Writes the composed frames: the drawn desktop, the island's panel at the
/// top centre, the cursor over both. H.264 at a high bitrate, re-encoded
/// small by the script afterwards.
final class FrameWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let pixels: CGSize
    let scale: CGFloat
    private let cursorImage: CGImage
    private let cursorSize: CGSize
    private let hotSpot: CGPoint

    init(url: URL, canvas: CGSize, scale: CGFloat) throws {
        try? FileManager.default.removeItem(at: url)
        pixels = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        self.scale = scale
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(pixels.width),
            AVVideoHeightKey: Int(pixels.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 24_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(pixels.width),
            kCVPixelBufferHeightKey as String: Int(pixels.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let arrow = NSCursor.arrow
        cursorSize = arrow.image.size
        hotSpot = arrow.hotSpot
        var rect = NSRect(origin: .zero, size: arrow.image.size)
        cursorImage = arrow.image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    }

    /// One frame: `panel` is drawn at `panelSize` points from the canvas's
    /// top edge, what it centres on (`anchorOffset` from its left edge) at
    /// the canvas's middle.
    func append(frame: Int, backdrop: CGImage, panel: CGImage?, panelSize: CGSize, anchorOffset: CGFloat, cursor: CGPoint?, ring: Double?) {
        guard let pool = adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: Int(pixels.width), height: Int(pixels.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        context.interpolationQuality = .high
        let height = pixels.height
        context.draw(backdrop, in: CGRect(origin: .zero, size: pixels))
        if let panel {
            let width = panelSize.width * scale, tall = panelSize.height * scale
            context.draw(panel, in: CGRect(x: pixels.width / 2 - anchorOffset * scale, y: height - tall, width: width, height: tall))
        }
        if let cursor {
            if let ring {
                let radius = (6 + 14 * ring) * scale
                context.setStrokeColor(CGColor(gray: 1, alpha: 0.7 * (1 - ring)))
                context.setLineWidth(2 * scale)
                context.strokeEllipse(in: CGRect(x: cursor.x * scale - radius, y: height - cursor.y * scale - radius, width: radius * 2, height: radius * 2))
            }
            let origin = CGPoint(x: (cursor.x - hotSpot.x) * scale, y: height - (cursor.y - hotSpot.y + cursorSize.height) * scale)
            context.draw(cursorImage, in: CGRect(origin: origin, size: CGSize(width: cursorSize.width * scale, height: cursorSize.height * scale)))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { usleep(1000) }
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(Scene.fps)))
    }

    func finish() async {
        input.markAsFinished()
        await writer.finishWriting()
    }
}
