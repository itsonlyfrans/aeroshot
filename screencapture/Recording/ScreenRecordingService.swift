import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Records screen content to MP4 via SCStream + AVAssetWriter.
/// Reuses ScreenCaptureService filter construction for area/display captures.
final class ScreenRecordingService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

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
    private var isRecording = false
    private var includeSystemAudio = false
    private var includeMicrophone = false
    private var videoFramesWritten = 0
    private let sampleQueue = DispatchQueue(label: "ScreenRecordingService.samples")
    /// Serial queue — all writer mutations and finishWriting happen here.
    private let writerQueue = DispatchQueue(label: "ScreenRecordingService.writer")

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
        self.isRecording = true

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
        isRecording = false
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
        isRecording = false
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

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording else { return }
        guard Self.isCompleteFrame(sampleBuffer) else { return }

        writerQueue.async { [weak self] in
            guard let self, self.isRecording || self.sessionStarted else { return }
            switch type {
            case .screen:
                self.handleVideoSample(sampleBuffer)
            case .audio:
                self.handleAudioSample(sampleBuffer)
            case .microphone:
                if #available(macOS 15.0, *) {
                    self.handleMicrophoneSample(sampleBuffer)
                }
            @unknown default:
                break
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
        writer.finishWriting { [weak self] in
            defer { self?.stopWriterState() }
            if writer.status == .completed {
                continuation.resume(returning: url)
            } else {
                try? FileManager.default.removeItem(at: url)
                continuation.resume(throwing: writer.error ?? RecordingError.writerSetupFailed)
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
