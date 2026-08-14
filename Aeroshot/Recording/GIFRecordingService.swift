import CoreImage
import ImageIO
import os
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Records a region to a bounded, disk-backed spool and streams it into an animated GIF.
nonisolated final class GIFRecordingService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum GIFError: LocalizedError {
        case noFrames
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noFrames: "No GIF frames were captured."
            case .writeFailed: "Aeroshot could not finalize the GIF recording."
            }
        }
    }

    var unexpectedStopHandler: (@Sendable () -> Void)?

    private let captureStart = CaptureStartGate<SCStream>()
    private let spoolState = OSAllocatedUnfairLock<GIFFrameSpool?>(initialState: nil)
    private let recordingState = OSAllocatedUnfairLock(initialState: false)
    private let limits: GIFFrameSpool.Limits
    private let sampleQueue = DispatchQueue(label: "GIFRecordingService.samples")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var frameDurationMicroseconds: Int64 = 100_000

    init(maxFrames: Int = 18_000, maximumSpoolBytes: Int64 = 4 * 1_024 * 1_024 * 1_024) {
        limits = .init(maximumFrameCount: maxFrames, maximumBytes: maximumSpoolBytes)
        super.init()
    }

    func start(filter: SCContentFilter, configuration: SCStreamConfiguration, fps: Int = 10) async throws {
        let generation = captureStart.beginStartOperation()
        defer { captureStart.startOperationDidFinish() }
        do {
            try beginCapture(fps: fps)
        } catch {
            _ = captureStart.invalidate()
            recordingState.withLock { $0 = false }
            throw error
        }

        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.showsCursor = true
        configuration.queueDepth = 3
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        do {
            try await stream.startCapture()
        } catch {
            _ = captureStart.invalidate()
            recordingState.withLock { $0 = false }
            throw error
        }
        guard captureStart.complete(stream, for: generation) else {
            try? await stream.stopCapture()
            throw CancellationError()
        }
    }

    func beginCapture(fps: Int) throws {
        guard fps > 0 else { throw GIFCoreError.invalidSettings }
        PerformanceInstrumentation.counters.reset()
        GIFFrameSpool.recoverAbandonedSpools()
        let spool = try GIFFrameSpool(limits: limits)
        spoolState.withLock { old in old?.removeAll(); old = spool }
        frameDurationMicroseconds = Int64((1_000_000.0 / Double(fps)).rounded())
        recordingState.withLock { $0 = true }
    }

    func stop(outputURL: URL, frameDelay: Double = 0.1) async throws -> URL {
        recordingState.withLock { $0 = false }
        let stream = captureStart.invalidate()
        try? await stream?.stopCapture()
        guard let spool = spoolState.withLock({ value -> GIFFrameSpool? in let result = value; value = nil; return result }) else {
            throw GIFError.noFrames
        }
        defer {
            spool.removeAll()
            PerformanceInstrumentation.counters.setScratchBytes(0)
        }
        do {
            var document = try spool.makeDocument()
            let requestedDuration = Int64((frameDelay * 1_000_000).rounded())
            if requestedDuration > 0 { try document.setDuration(requestedDuration, for: document.frames.indices) }
            _ = try await GIFWriter().write(document, to: outputURL)
            return outputURL
        } catch GIFCoreError.noFrames { throw GIFError.noFrames }
        catch { throw GIFError.writeFailed }
    }

    func cancel() async {
        recordingState.withLock { $0 = false }
        let stream = captureStart.invalidate()
        try? await stream?.stopCapture()
        await captureStart.waitForStartOperations()
        spoolState.withLock { spool in
            spool?.removeAll()
            spool = nil
        }
        PerformanceInstrumentation.counters.setScratchBytes(0)
    }

    var acceptsFrames: Bool { recordingState.withLock { $0 } }
    var hasBufferedFrames: Bool { spoolState.withLock { $0 != nil } }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard recordingState.withLock({ $0 }), type == .screen else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        PerformanceInstrumentation.counters.recordArrival(.gif)
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = ciContext.createCGImage(ci, from: ci.extent) else {
            PerformanceInstrumentation.counters.recordCompletion(.gif, appended: false)
            return
        }
        let appendState = PerformanceInstrumentation.signposter.beginInterval("GIFSpoolAppend")
        let result: (Bool, Int64)
        do {
            result = try spoolState.withLock { spool in
                guard let spool else { return (false, 0) }
                let accepted = try spool.append(image, durationMicroseconds: frameDurationMicroseconds)
                return (accepted, spool.statistics.byteCount)
            }
        } catch {
            PerformanceInstrumentation.counters.recordTerminalError(error)
            result = (false, spoolState.withLock { $0?.statistics.byteCount ?? 0 })
        }
        PerformanceInstrumentation.signposter.endInterval("GIFSpoolAppend", appendState)
        let accepted = result.0
        PerformanceInstrumentation.counters.setScratchBytes(result.1)
        PerformanceInstrumentation.counters.recordCompletion(.gif, appended: accepted)
        if !accepted { NSLog("GIF spool reached its configured bound; dropping frame") }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("GIF stream stopped: \(error)")
        PerformanceInstrumentation.counters.recordTerminalError(error)
        handleUnexpectedStop()
    }

    private func handleUnexpectedStop() {
        let wasRecording = recordingState.withLock { state in
            let result = state
            state = false
            return result
        }
        guard wasRecording else { return }
        unexpectedStopHandler?()
    }

#if DEBUG
    func simulateUnexpectedStopForTesting() { handleUnexpectedStop() }
#endif
}
