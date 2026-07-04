import CoreImage
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Records a region to an animated GIF by sampling SCStream frames.
final class GIFRecordingService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

    enum GIFError: Error {
        case noFrames
        case writeFailed
    }

    private var stream: SCStream?
    private var frames: [CGImage] = []
    private var frameLock = NSLock()
    private var isRecording = false
    private let maxFrames: Int
    private let sampleQueue = DispatchQueue(label: "GIFRecordingService.samples")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    init(maxFrames: Int = 300) {
        self.maxFrames = maxFrames
    }

    func start(filter: SCContentFilter, configuration: SCStreamConfiguration, fps: Int = 10) async throws {
        frameLock.lock()
        frames = []
        frameLock.unlock()
        isRecording = true

        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.showsCursor = true
        configuration.queueDepth = 3

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop(outputURL: URL, frameDelay: Double = 0.1) async throws -> URL {
        isRecording = false
        let stream = self.stream
        self.stream = nil
        try? await stream?.stopCapture()

        frameLock.lock()
        let captured = frames
        frames = []
        frameLock.unlock()

        guard !captured.isEmpty else { throw GIFError.noFrames }
        guard writeGIF(frames: captured, to: outputURL, frameDelay: frameDelay) else {
            throw GIFError.writeFailed
        }
        return outputURL
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording, type == .screen else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }

        frameLock.lock()
        if frames.count < maxFrames {
            frames.append(cg)
        }
        frameLock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("GIF stream stopped: \(error)")
    }

    private func writeGIF(frames: [CGImage], to url: URL, frameDelay: Double) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                         UTType.gif.identifier as CFString,
                                                         frames.count,
                                                         nil)
        else { return false }

        let fileProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        CGImageDestinationSetProperties(dest, fileProps)

        for frame in frames {
            let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]] as CFDictionary
            CGImageDestinationAddImage(dest, frame, frameProps)
        }
        return CGImageDestinationFinalize(dest)
    }
}
