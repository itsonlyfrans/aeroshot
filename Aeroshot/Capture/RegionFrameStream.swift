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
    private let frames = FrameContinuationStore()
    private let stateLock = NSLock()
    private var stopped = false
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

        let output = AsyncStream<CGImage>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            frames.install(continuation)
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        let shouldStop = withStateLock {
            if stopped { return true }
            self.stream = stream
            return false
        }
        if shouldStop {
            frames.finish()
            try? await stream.stopCapture()
        }
        return output
    }

    func stop() {
        frames.finish()
        let stream = withStateLock { () -> SCStream? in
            stopped = true
            defer { self.stream = nil }
            return self.stream
        }
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
        frames.yield(cg)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        frames.finish()
        withStateLock {
            self.stream = nil
            self.stopped = true
        }
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}

/// `SCStreamOutput` delivers on a private queue while the controller starts
/// and stops on the main actor. Keeping continuation access in one lock-backed
/// object prevents a callback from yielding through a continuation that is
/// concurrently being finished and cleared.
nonisolated final class FrameContinuationStore: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<CGImage>.Continuation?

    func install(_ continuation: AsyncStream<CGImage>.Continuation) {
        withLock { self.continuation = continuation }
    }

    func yield(_ image: CGImage) {
        let continuation = withLock { self.continuation }
        continuation?.yield(image)
    }

    func finish() {
        let continuation = withLock { () -> AsyncStream<CGImage>.Continuation? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.finish()
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
