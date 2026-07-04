import ScreenCaptureKit
import CoreImage

/// Continuous frame delivery for a fixed display region via SCStream.
///
/// Unlike SCScreenshotManager (a full request/response round trip per grab),
/// the stream pushes frames as the content changes, so scrolling capture can
/// stitch at ~30fps with heavily overlapping frames. Frames are delivered
/// through an AsyncStream with a latest-wins buffer: if the consumer is still
/// matching the previous frame, intermediate frames are dropped rather than
/// queued, which keeps the composite live without falling behind.
final class RegionFrameStream: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

    private var stream: SCStream?
    private var continuation: AsyncStream<CGImage>.Continuation?
    private let sampleQueue = DispatchQueue(label: "RegionFrameStream.samples")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Starts capturing `rectInDisplayTopLeftPoints` and returns the frame
    /// stream. The stream finishes when `stop()` is called or capture fails.
    func start(rect rectInDisplayTopLeftPoints: CGRect,
               display: DisplayInfo,
               excludingWindows: [SCWindow],
               fps: Int = 30) async throws -> AsyncStream<CGImage> {
        let filter = ScreenCaptureService.filter(for: display, excludingWindows: excludingWindows)
        let config = SCStreamConfiguration()
        config.sourceRect = rectInDisplayTopLeftPoints
        config.width = Int((rectInDisplayTopLeftPoints.width * display.scale).rounded())
        config.height = Int((rectInDisplayTopLeftPoints.height * display.scale).rounded())
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 3

        let frames = AsyncStream<CGImage>(bufferingPolicy: .bufferingNewest(1)) { cont in
            self.continuation = cont
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
        return frames
    }

    func stop() {
        continuation?.finish()
        continuation = nil
        let stream = self.stream
        self.stream = nil
        Task { try? await stream?.stopCapture() }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        continuation?.yield(cg)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        continuation?.finish()
        continuation = nil
    }
}
