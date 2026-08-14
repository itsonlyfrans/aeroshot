import AVFoundation
import CoreMedia
import os
import ScreenCaptureKit

/// Owns one stream-start attempt and rejects a stream that completes after cancel.
nonisolated final class CaptureStartGate<Handle>: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var isActive = false
    private var handle: Handle?
    private var startOperationCount = 0
    private var startOperationWaiters: [CheckedContinuation<Void, Never>] = []

    /// Starts cancellation tracking before work that can suspend creates a handle.
    func beginStartOperation() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        isActive = true
        handle = nil
        startOperationCount += 1
        return generation
    }

    /// Claims an idle start operation without replacing its current owner.
    func tryBeginStartOperation() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        // A cancelled starter still owns cleanup until its deferred finish runs.
        // Do not let a retry overlap that work and start a second capture.
        guard !isActive, startOperationCount == 0 else { return nil }
        generation &+= 1
        isActive = true
        handle = nil
        startOperationCount += 1
        return generation
    }

    func isActive(for generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isActive && self.generation == generation
    }

    func complete(_ handle: Handle, for generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isActive, self.generation == generation else { return false }
        self.handle = handle
        return true
    }

    func invalidate() -> Handle? {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        isActive = false
        defer { handle = nil }
        return handle
    }

    func startOperationDidBegin() {
        lock.lock()
        startOperationCount += 1
        lock.unlock()
    }

    func startOperationDidFinish() {
        lock.lock()
        guard startOperationCount > 0 else {
            lock.unlock()
            return
        }
        startOperationCount -= 1
        guard startOperationCount == 0 else {
            lock.unlock()
            return
        }
        let waiters = startOperationWaiters
        startOperationWaiters = []
        lock.unlock()
        waiters.forEach { $0.resume() }
    }

    func waitForStartOperations() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            guard startOperationCount > 0 else {
                lock.unlock()
                continuation.resume()
                return
            }
            startOperationWaiters.append(continuation)
            lock.unlock()
        }
    }
}

/// Records screen content to MP4 via SCStream + AVAssetWriter.
/// Reuses ScreenCaptureService filter construction for area/display captures.
nonisolated final class ScreenRecordingService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

    enum AudioMeterSource: Sendable { case system, microphone }
    var audioLevelHandler: (@Sendable (AudioMeterSource, Float) -> Void)?
    var timelineResumedHandler: (@Sendable () -> Void)?
    var unexpectedStopHandler: (@Sendable () -> Void)?
    var microphoneDeviceID: String?

    private struct SendableSampleBuffer: @unchecked Sendable {
        let value: CMSampleBuffer
    }

    private struct WriterFinishContext: @unchecked Sendable {
        let writer: AVAssetWriter
        let url: URL
    }

    private struct CaptureControlState {
        var isRecording = false
        var isPaused = false
        var latestSourceTime: CMTime?
        var resumeAtNextSample = false
        var resumeNeedsPauseAnchor = false
    }

    enum RecordingError: Error, LocalizedError {
        case writerSetupFailed
        case noFramesRecorded

        var errorDescription: String? {
            switch self {
            case .writerSetupFailed: return "Could not set up the video writer."
            case .noFramesRecorded: return "No video frames were captured."
            }
        }
    }

    private let captureStart = CaptureStartGate<SCStream>()
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var includeSystemAudio = false
    private var includeMicrophone = false
    private var videoFramesWritten = 0
    private var lastSystemAudioMeterTime: CMTime?
    private var lastMicrophoneMeterTime: CMTime?
    private let sampleQueue = DispatchQueue(label: "ScreenRecordingService.samples")
    /// Serial queue — all writer mutations and finishWriting happen here.
    private let writerQueue = DispatchQueue(label: "ScreenRecordingService.writer")
    /// Protects callback-visible recording and pause state.
    private let controlLock = NSLock()
    private var controlState = CaptureControlState()
    /// This timebase corrects media and effect events from the same source timestamps.
    let mediaTimeline: RecordingMediaTimeline

    init(mediaTimeline: RecordingMediaTimeline = RecordingMediaTimeline()) {
        self.mediaTimeline = mediaTimeline
        super.init()
    }

    /// Starts recording. Caller must supply a filter and matching stream configuration.
    func start(filter: SCContentFilter,
               configuration: SCStreamConfiguration,
               outputURL: URL,
               includeSystemAudio: Bool,
               includeMicrophone: Bool = false) async throws {
        PerformanceInstrumentation.counters.reset()
        stopWriterState()
        mediaTimeline.reset()
        try? FileManager.default.removeItem(at: outputURL)

        self.outputURL = outputURL
        self.includeSystemAudio = includeSystemAudio
        self.includeMicrophone = includeMicrophone
        self.videoFramesWritten = 0
        self.sessionStarted = false
        let generation = captureStart.beginStartOperation()
        defer { captureStart.startOperationDidFinish() }
        setRecordingActive(true)

        // Audio inputs must exist before the first video frame starts writing.
        // The video input waits for the source format so its dimensions match.
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
        writer.initialMovieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
        assetWriter = writer

        if includeSystemAudio {
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
        }
        if includeMicrophone {
            if #available(macOS 15.0, *) {
                configuration.captureMicrophone = true
                configuration.microphoneCaptureDeviceID = microphoneDeviceID
            } else {
                self.includeMicrophone = false
            }
        }
        do {
            try Self.prepareAudioInputs(for: writer,
                                        includeSystemAudio: self.includeSystemAudio,
                                        includeMicrophone: self.includeMicrophone,
                                        assign: { [weak self] systemAudio, microphone in
                                            self?.audioInput = systemAudio
                                            self?.micInput = microphone
                                        })
        } catch {
            stopWriterState()
            setRecordingActive(false)
            throw error
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if self.includeSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }
        if self.includeMicrophone {
            if #available(macOS 15.0, *) {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
            }
        }
        do {
            try await stream.startCapture()
        } catch {
            _ = captureStart.invalidate()
            setRecordingActive(false)
            throw error
        }
        guard captureStart.complete(stream, for: generation) else {
            try? await stream.stopCapture()
            throw CancellationError()
        }
    }

    func cancel() async {
        setRecordingActive(false)
        let stream = captureStart.invalidate()
        try? await stream?.stopCapture()
        await captureStart.waitForStartOperations()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerQueue.async { [weak self] in
                if let url = self?.outputURL {
                    try? FileManager.default.removeItem(at: url)
                }
                self?.stopWriterState()
                continuation.resume()
            }
        }
    }

    func stop() async throws -> URL {
        setRecordingActive(false)
        let stream = captureStart.invalidate()
        try? await stream?.stopCapture()

        return try await withCheckedThrowingContinuation { continuation in
            writerQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: RecordingError.writerSetupFailed)
                    return
                }
                self.finishWriting(continuation: continuation)
            }
        }
    }

    /// Pauses sample delivery at the latest observed source timestamp.
    /// Safe to call concurrently with ScreenCaptureKit callbacks.
    @discardableResult
    func pause() -> Bool {
        controlLock.lock()
        guard controlState.isRecording, !controlState.isPaused else {
            controlLock.unlock()
            return false
        }
        controlState.isPaused = true
        controlState.resumeAtNextSample = false
        let sourceTime = controlState.latestSourceTime
        controlLock.unlock()

        _ = mediaTimeline.pause(at: sourceTime)
        return true
    }

    /// Resumes delivery. The first sample supplies the exact end of the pause.
    /// Safe to call concurrently with ScreenCaptureKit callbacks.
    @discardableResult
    func resume() -> Bool {
        controlLock.lock()
        guard controlState.isRecording, controlState.isPaused else {
            controlLock.unlock()
            return false
        }
        controlState.isPaused = false
        controlState.resumeAtNextSample = true
        controlState.resumeNeedsPauseAnchor = controlState.latestSourceTime == nil
        controlLock.unlock()
        return true
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let isComplete = Self.isCompleteFrame(sampleBuffer)
        controlLock.lock()
        guard controlState.isRecording else {
            controlLock.unlock()
            return
        }
        guard !controlState.isPaused else {
            controlLock.unlock()
            PerformanceInstrumentation.counters.recordPausedSample()
            return
        }
        guard isComplete else {
            controlLock.unlock()
            PerformanceInstrumentation.counters.recordIncompleteSample()
            return
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if presentationTime.isNumeric {
            if let latestSourceTime = controlState.latestSourceTime {
                if CMTimeCompare(presentationTime, latestSourceTime) > 0 {
                    controlState.latestSourceTime = presentationTime
                }
            } else {
                controlState.latestSourceTime = presentationTime
            }
        }
        controlLock.unlock()
        mediaTimeline.observe(presentationTime)

        guard let track = Self.timelineTrack(for: type) else { return }
        let sampleKind: PerformanceSampleKind
        let pendingLimit: Int
        switch track {
        case .video:
            sampleKind = .video
            pendingLimit = 2
        case .systemAudio:
            sampleKind = .systemAudio
            pendingLimit = 8
        case .microphone:
            sampleKind = .microphone
            pendingLimit = 8
        }
        guard PerformanceInstrumentation.counters.reservePending(sampleKind, limit: pendingLimit) else { return }
        let queueWaitState = PerformanceInstrumentation.signposter.beginInterval("WriterQueueWait")
        let buffered = SendableSampleBuffer(value: sampleBuffer)
        writerQueue.async { [weak self] in
            PerformanceInstrumentation.signposter.endInterval("WriterQueueWait", queueWaitState)
            guard let self else {
                PerformanceInstrumentation.counters.recordCompletion(sampleKind, appended: false)
                return
            }
            var result = (appended: false, backpressure: false)
            defer {
                PerformanceInstrumentation.counters.recordCompletion(
                    sampleKind,
                    appended: result.appended,
                    backpressure: result.backpressure,
                    terminalError: result.appended ? nil : self.assetWriter?.error?.localizedDescription
                )
            }
            guard self.isCaptureActive() || self.sessionStarted else { return }
            let resumeRequest = self.takeResumeRequest()
            if resumeRequest.pending {
                if resumeRequest.needsPauseAnchor {
                    _ = self.mediaTimeline.pause(at: presentationTime)
                }
                guard self.mediaTimeline.resume(at: presentationTime) else {
                    self.restoreResumeRequest(needsPauseAnchor: resumeRequest.needsPauseAnchor)
                    return
                }
                self.timelineResumedHandler?()
            }
            guard let corrected = self.retimedSampleBuffer(buffered.value, track: track) else { return }
            switch track {
            case .video:
                result = self.handleVideoSample(corrected)
            case .systemAudio:
                result = self.handleAudioSample(corrected)
            case .microphone:
                if #available(macOS 15.0, *) {
                    result = self.handleMicrophoneSample(corrected)
                }
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Recording stream stopped: \(error)")
        PerformanceInstrumentation.counters.recordTerminalError(error)
        handleUnexpectedStop()
    }

    private func handleUnexpectedStop() {
        controlLock.lock()
        let wasRecording = controlState.isRecording
        controlState = CaptureControlState()
        controlLock.unlock()
        guard wasRecording else { return }
        unexpectedStopHandler?()
    }

#if DEBUG
    func installActiveCaptureForUnexpectedStopTesting() { setRecordingActive(true) }
    func simulateUnexpectedStopForTesting() { handleUnexpectedStop() }
#endif

    // MARK: - Writer

    private func handleVideoSample(_ sampleBuffer: CMSampleBuffer) -> (appended: Bool, backpressure: Bool) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return (false, false) }

        if videoInput == nil {
            guard setupVideoInput(from: sampleBuffer) else { return (false, false) }
        }
        guard sessionStarted, let input = videoInput else { return (false, false) }
        guard input.isReadyForMoreMediaData else { return (false, true) }

        if input.append(sampleBuffer) {
            videoFramesWritten += 1
            return (true, false)
        } else if let error = assetWriter?.error {
            NSLog("Video append failed: \(error)")
        }
        return (false, false)
    }

    private func handleAudioSample(_ sampleBuffer: CMSampleBuffer) -> (appended: Bool, backpressure: Bool) {
        guard includeSystemAudio, sessionStarted else { return (false, false) }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return (false, false) }
        if shouldUpdateAudioMeter(for: sampleBuffer, microphone: false) {
            audioLevelHandler?(.system, Self.normalizedPeakLevel(sampleBuffer))
        }
        guard let input = audioInput else { return (false, false) }
        guard input.isReadyForMoreMediaData else { return (false, true) }
        guard input.append(sampleBuffer) else {
            if let error = assetWriter?.error {
                NSLog("Audio append failed: \(error)")
            }
            return (false, false)
        }
        return (true, false)
    }

    private func handleMicrophoneSample(_ sampleBuffer: CMSampleBuffer) -> (appended: Bool, backpressure: Bool) {
        guard includeMicrophone, sessionStarted else { return (false, false) }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return (false, false) }
        if shouldUpdateAudioMeter(for: sampleBuffer, microphone: true) {
            audioLevelHandler?(.microphone, Self.normalizedPeakLevel(sampleBuffer))
        }
        guard let input = micInput else { return (false, false) }
        guard input.isReadyForMoreMediaData else { return (false, true) }
        guard input.append(sampleBuffer) else {
            if let error = assetWriter?.error {
                NSLog("Microphone append failed: \(error)")
            }
            return (false, false)
        }
        return (true, false)
    }

    private func shouldUpdateAudioMeter(for sampleBuffer: CMSampleBuffer, microphone: Bool) -> Bool {
        let current = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let previous = microphone ? lastMicrophoneMeterTime : lastSystemAudioMeterTime
        guard Self.shouldUpdateAudioMeter(previous: previous, current: current) else { return false }
        if microphone {
            lastMicrophoneMeterTime = current
        } else {
            lastSystemAudioMeterTime = current
        }
        return true
    }

    static func shouldUpdateAudioMeter(previous: CMTime?, current: CMTime) -> Bool {
        guard current.isNumeric else { return false }
        guard let previous, previous.isNumeric else { return true }
        if CMTimeCompare(current, previous) < 0 { return true }
        return CMTimeCompare(
            CMTimeSubtract(current, previous),
            CMTime(value: 1, timescale: 20)
        ) >= 0
    }

    static func normalizedPeakLevel(_ sampleBuffer: CMSampleBuffer) -> Float {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }
        let byteCount = CMBlockBufferGetDataLength(block)
        guard byteCount > 0 else { return 0 }
        var data = Data(count: byteCount)
        guard data.withUnsafeMutableBytes({ raw in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: raw.baseAddress!)
        }) == kCMBlockBufferNoErr else { return 0 }
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSigned = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        if isFloat, asbd.mBitsPerChannel == 32 {
            return data.withUnsafeBytes { raw in
                min(1, raw.bindMemory(to: Float.self).reduce(Float.zero) { max($0, abs($1.isFinite ? $1 : 0)) })
            }
        }
        if isSigned, asbd.mBitsPerChannel == 16 {
            return data.withUnsafeBytes { raw in
                raw.bindMemory(to: Int16.self).reduce(Float.zero) { max($0, abs(Float($1) / Float(Int16.max))) }
            }
        }
        return 0
    }

    static func prepareAudioInputs(
        for writer: AVAssetWriter,
        includeSystemAudio: Bool,
        includeMicrophone: Bool,
        assign: (AVAssetWriterInput?, AVAssetWriterInput?) -> Void
    ) throws {
        func makeInput(sampleRate: Double, channels: Int, bitRate: Int) -> AVAssetWriterInput {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: bitRate,
            ])
            input.expectsMediaDataInRealTime = true
            return input
        }

        let systemAudio = includeSystemAudio ? makeInput(sampleRate: 48_000, channels: 2, bitRate: 128_000) : nil
        let microphone = includeMicrophone ? makeInput(sampleRate: 48_000, channels: 1, bitRate: 96_000) : nil
        for input in [systemAudio, microphone].compactMap({ $0 }) {
            guard writer.canAdd(input) else { throw RecordingError.writerSetupFailed }
            writer.add(input)
        }
        assign(systemAudio, microphone)
    }

    @discardableResult
    private func setupVideoInput(from sampleBuffer: CMSampleBuffer) -> Bool {
        guard let writer = assetWriter,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        else { return false }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 4,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video,
                                       outputSettings: videoSettings,
                                       sourceFormatHint: formatDescription)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        videoInput = input

        writer.startWriting()
        writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        sessionStarted = true
        return true
    }

    private func finishWriting(continuation: CheckedContinuation<URL, Error>) {
        guard let writer = assetWriter, let url = outputURL else {
            continuation.resume(throwing: RecordingError.writerSetupFailed)
            stopWriterState()
            return
        }

        guard videoFramesWritten > 0 else {
            try? FileManager.default.removeItem(at: url)
            continuation.resume(throwing: RecordingError.noFramesRecorded)
            stopWriterState()
            return
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        micInput?.markAsFinished()
        let context = WriterFinishContext(writer: writer, url: url)
        writer.finishWriting { [weak self] in
            self?.mediaTimeline.finalize()
            defer { self?.stopWriterState() }
            if context.writer.status == .completed {
                continuation.resume(returning: context.url)
            } else {
                continuation.resume(throwing: context.writer.error ?? RecordingError.writerSetupFailed)
            }
        }
    }

    private func stopWriterState() {
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        micInput = nil
        outputURL = nil
        sessionStarted = false
        includeSystemAudio = false
        includeMicrophone = false
        videoFramesWritten = 0
        lastSystemAudioMeterTime = nil
        lastMicrophoneMeterTime = nil
    }

    private func setRecordingActive(_ active: Bool) {
        controlLock.lock()
        controlState = CaptureControlState(isRecording: active)
        controlLock.unlock()
    }

    private func isCaptureActive() -> Bool {
        controlLock.lock()
        defer { controlLock.unlock() }
        return controlState.isRecording
    }

    private func takeResumeRequest() -> (pending: Bool, needsPauseAnchor: Bool) {
        controlLock.lock()
        defer { controlLock.unlock() }
        guard controlState.resumeAtNextSample else { return (false, false) }
        controlState.resumeAtNextSample = false
        let needsPauseAnchor = controlState.resumeNeedsPauseAnchor
        controlState.resumeNeedsPauseAnchor = false
        return (true, needsPauseAnchor)
    }

    private func restoreResumeRequest(needsPauseAnchor: Bool) {
        controlLock.lock()
        if controlState.isRecording, !controlState.isPaused {
            controlState.resumeAtNextSample = true
            controlState.resumeNeedsPauseAnchor = needsPauseAnchor
        }
        controlLock.unlock()
    }

    private static func timelineTrack(for type: SCStreamOutputType) -> RecordingTimelineClock.Track? {
        switch type {
        case .screen: return .video
        case .audio: return .systemAudio
        case .microphone: return .microphone
        @unknown default: return nil
        }
    }

    /// Copies all timing entries with one presentation-time correction. Decode
    /// timestamps receive the same delta and sample durations remain unchanged.
    private func retimedSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        track: RecordingTimelineClock.Track
    ) -> CMSampleBuffer? {
        let sourcePresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let correctedPresentationTime = mediaTimeline.correctedTime(
            for: sourcePresentationTime,
            track: track
        ) else { return nil }

        let delta = CMTimeSubtract(correctedPresentationTime, sourcePresentationTime)
        if CMTimeCompare(delta, .zero) == 0 { return sampleBuffer }

        var entryCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &entryCount
        ) == noErr, entryCount > 0 else { return nil }

        var timings = Array(repeating: CMSampleTimingInfo(), count: entryCount)
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: entryCount,
            arrayToFill: &timings,
            entriesNeededOut: &entryCount
        ) == noErr else { return nil }

        for index in timings.indices {
            if timings[index].presentationTimeStamp.isNumeric {
                timings[index].presentationTimeStamp = CMTimeAdd(
                    timings[index].presentationTimeStamp,
                    delta
                )
            }
            if timings[index].decodeTimeStamp.isNumeric {
                timings[index].decodeTimeStamp = CMTimeAdd(
                    timings[index].decodeTimeStamp,
                    delta
                )
            }
        }

        var correctedBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: entryCount,
            sampleTimingArray: &timings,
            sampleBufferOut: &correctedBuffer
        ) == noErr else { return nil }
        return correctedBuffer
    }

    /// ScreenCaptureKit marks idle/blank frames — never feed those to AVAssetWriter.
    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard CMSampleBufferIsValid(sampleBuffer) else { return false }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw)
        else { return true }
        return status == .complete
    }

    /// H.264 requires even dimensions.
    static func evenPixelSize(width: Int, height: Int) -> (width: Int, height: Int) {
        (max(2, width & ~1), max(2, height & ~1))
    }
}
