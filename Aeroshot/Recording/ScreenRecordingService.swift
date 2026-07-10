import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Records screen content to MP4 via SCStream + AVAssetWriter.
/// Reuses ScreenCaptureService filter construction for area/display captures.
nonisolated final class ScreenRecordingService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

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

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var includeSystemAudio = false
    private var includeMicrophone = false
    private var videoFramesWritten = 0
    private let sampleQueue = DispatchQueue(label: "ScreenRecordingService.samples")
    /// Serial queue — all writer mutations and finishWriting happen here.
    private let writerQueue = DispatchQueue(label: "ScreenRecordingService.writer")
    /// Protects callback-visible recording and pause state.
    private let controlLock = NSLock()
    private var controlState = CaptureControlState()
    /// Mutated only on writerQueue; this one clock corrects all writer tracks.
    private var timelineClock = RecordingTimelineClock()

    /// Starts recording. Caller must supply a filter and matching stream configuration.
    func start(filter: SCContentFilter,
               configuration: SCStreamConfiguration,
               outputURL: URL,
               includeSystemAudio: Bool,
               includeMicrophone: Bool = false) async throws {
        stopWriterState()
        try? FileManager.default.removeItem(at: outputURL)

        self.outputURL = outputURL
        self.includeSystemAudio = includeSystemAudio
        self.includeMicrophone = includeMicrophone
        self.videoFramesWritten = 0
        self.sessionStarted = false
        setRecordingActive(true)

        // Writer inputs are created lazily from the first complete video frame so
        // sourceFormatHint matches what ScreenCaptureKit actually delivers.
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        assetWriter = writer

        if includeSystemAudio {
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
        }
        if includeMicrophone {
            if #available(macOS 15.0, *) {
                configuration.captureMicrophone = true
            } else {
                self.includeMicrophone = false
            }
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if includeSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }
        if includeMicrophone {
            if #available(macOS 15.0, *) {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
            }
        }
        try await stream.startCapture()
        self.stream = stream
    }

    func cancel() async {
        setRecordingActive(false)
        let stream = self.stream
        self.stream = nil
        try? await stream?.stopCapture()

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
        let stream = self.stream
        self.stream = nil
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

        if let sourceTime {
            writerQueue.sync {
                timelineClock.pause(at: sourceTime)
            }
        }
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
        guard Self.isCompleteFrame(sampleBuffer) else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        controlLock.lock()
        guard controlState.isRecording, !controlState.isPaused else {
            controlLock.unlock()
            return
        }
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

        let buffered = SendableSampleBuffer(value: sampleBuffer)
        let outputType = type
        writerQueue.async { [weak self] in
            guard let self, self.isCaptureActive() || self.sessionStarted else { return }
            guard let track = Self.timelineTrack(for: outputType) else { return }
            let resumeRequest = self.takeResumeRequest()
            if resumeRequest.pending {
                if resumeRequest.needsPauseAnchor {
                    self.timelineClock.pause(at: presentationTime)
                }
                guard self.timelineClock.resume(at: presentationTime) else {
                    self.restoreResumeRequest(needsPauseAnchor: resumeRequest.needsPauseAnchor)
                    return
                }
            }
            guard let corrected = self.retimedSampleBuffer(buffered.value, track: track) else { return }
            switch track {
            case .video:
                self.handleVideoSample(corrected)
            case .systemAudio:
                self.handleAudioSample(corrected)
            case .microphone:
                if #available(macOS 15.0, *) {
                    self.handleMicrophoneSample(corrected)
                }
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Recording stream stopped: \(error)")
    }

    // MARK: - Writer

    private func handleVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        if videoInput == nil {
            guard setupVideoInput(from: sampleBuffer) else { return }
        }
        guard sessionStarted, let input = videoInput else { return }
        guard input.isReadyForMoreMediaData else { return }

        if input.append(sampleBuffer) {
            videoFramesWritten += 1
        } else if let error = assetWriter?.error {
            NSLog("Video append failed: \(error)")
        }
    }

    private func handleAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard includeSystemAudio, sessionStarted else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let input = audioInput, input.isReadyForMoreMediaData else { return }
        if !input.append(sampleBuffer), let error = assetWriter?.error {
            NSLog("Audio append failed: \(error)")
        }
    }

    private func handleMicrophoneSample(_ sampleBuffer: CMSampleBuffer) {
        guard includeMicrophone, sessionStarted else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if micInput == nil {
            setupMicInput(from: sampleBuffer)
        }
        guard let input = micInput, input.isReadyForMoreMediaData else { return }
        if !input.append(sampleBuffer), let error = assetWriter?.error {
            NSLog("Microphone append failed: \(error)")
        }
    }

    private func setupMicInput(from sampleBuffer: CMSampleBuffer) {
        guard let writer = assetWriter, micInput == nil else { return }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) {
            writer.add(input)
            micInput = input
        }
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

        if includeSystemAudio, audioInput == nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput) {
                writer.add(aInput)
                audioInput = aInput
            }
        }

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
            defer { self?.stopWriterState() }
            if context.writer.status == .completed {
                continuation.resume(returning: context.url)
            } else {
                try? FileManager.default.removeItem(at: context.url)
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
        timelineClock = RecordingTimelineClock()
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
        guard let correctedPresentationTime = timelineClock.correctedTime(
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
