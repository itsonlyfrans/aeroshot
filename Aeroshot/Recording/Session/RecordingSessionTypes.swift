import Foundation

nonisolated enum RecordingSessionModelError: Error, Equatable {
    case invalidDimensions
    case invalidFrameRate
    case invalidCountdown
    case invalidSpaceEstimate
    case invalidDeviceIdentifier
    case invalidOutputByteCount
}

nonisolated enum RecordingSource: Codable, Equatable, Sendable {
    case display(id: String)
    case window(id: UInt32)
    case region(displayID: String, x: Int, y: Int, width: Int, height: Int)
}

nonisolated struct RecordingDimensions: Codable, Equatable, Sendable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw RecordingSessionModelError.invalidDimensions }
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey { case width, height }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            width: values.decode(Int.self, forKey: .width),
            height: values.decode(Int.self, forKey: .height)
        )
    }
}

nonisolated struct RecordingFrameRate: Codable, Equatable, Sendable {
    let framesPerSecond: Int

    init(framesPerSecond: Int) throws {
        guard (1...240).contains(framesPerSecond) else {
            throw RecordingSessionModelError.invalidFrameRate
        }
        self.framesPerSecond = framesPerSecond
    }

    private enum CodingKeys: String, CodingKey { case framesPerSecond }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(framesPerSecond: values.decode(Int.self, forKey: .framesPerSecond))
    }
}

nonisolated struct RecordingCountdown: Codable, Equatable, Sendable {
    let seconds: Int

    init(seconds: Int) throws {
        guard (0...10).contains(seconds) else { throw RecordingSessionModelError.invalidCountdown }
        self.seconds = seconds
    }

    private enum CodingKeys: String, CodingKey { case seconds }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(seconds: values.decode(Int.self, forKey: .seconds))
    }
}

nonisolated enum RecordingCursorMode: String, Codable, Equatable, Sendable {
    case hidden
    case visible
    case visibleWithClickEffects
}

nonisolated struct RecordingAudioConfiguration: Codable, Equatable, Sendable {
    let capturesSystemAudio: Bool
    let microphoneDeviceID: String?

    init(capturesSystemAudio: Bool, microphoneDeviceID: String? = nil) throws {
        if let microphoneDeviceID, microphoneDeviceID.isEmpty {
            throw RecordingSessionModelError.invalidDeviceIdentifier
        }
        self.capturesSystemAudio = capturesSystemAudio
        self.microphoneDeviceID = microphoneDeviceID
    }
}

nonisolated struct RecordingWebcamConfiguration: Codable, Equatable, Sendable {
    let deviceID: String

    init(deviceID: String) throws {
        guard !deviceID.isEmpty else { throw RecordingSessionModelError.invalidDeviceIdentifier }
        self.deviceID = deviceID
    }
}

nonisolated struct RecordingEventConfiguration: Codable, Equatable, Sendable {
    let capturesClicks: Bool
    let capturesKeystrokes: Bool

    /// Keystroke capture must never be silently enabled. The visible indicator
    /// requirement is carried in the persisted configuration for auditability.
    let showsKeystrokeCaptureIndicator: Bool

    init(
        capturesClicks: Bool = false,
        capturesKeystrokes: Bool = false,
        showsKeystrokeCaptureIndicator: Bool = false
    ) {
        self.capturesClicks = capturesClicks
        self.capturesKeystrokes = capturesKeystrokes
        self.showsKeystrokeCaptureIndicator = showsKeystrokeCaptureIndicator
    }
}

nonisolated struct RecordingSessionConfiguration: Codable, Equatable, Sendable {
    let source: RecordingSource
    let dimensions: RecordingDimensions
    let frameRate: RecordingFrameRate
    let cursorMode: RecordingCursorMode
    let audio: RecordingAudioConfiguration
    let webcam: RecordingWebcamConfiguration?
    let countdown: RecordingCountdown
    let events: RecordingEventConfiguration
    let requiredSpaceEstimateBytes: Int64

    init(
        source: RecordingSource,
        dimensions: RecordingDimensions,
        frameRate: RecordingFrameRate,
        cursorMode: RecordingCursorMode,
        audio: RecordingAudioConfiguration,
        webcam: RecordingWebcamConfiguration?,
        countdown: RecordingCountdown,
        events: RecordingEventConfiguration,
        requiredSpaceEstimateBytes: Int64
    ) throws {
        guard requiredSpaceEstimateBytes > 0 else {
            throw RecordingSessionModelError.invalidSpaceEstimate
        }
        if case let .region(_, _, _, width, height) = source {
            guard width > 0, height > 0 else { throw RecordingSessionModelError.invalidDimensions }
        }
        self.source = source
        self.dimensions = dimensions
        self.frameRate = frameRate
        self.cursorMode = cursorMode
        self.audio = audio
        self.webcam = webcam
        self.countdown = countdown
        self.events = events
        self.requiredSpaceEstimateBytes = requiredSpaceEstimateBytes
    }

    private enum CodingKeys: String, CodingKey {
        case source, dimensions, frameRate, cursorMode, audio, webcam, countdown, events
        case requiredSpaceEstimateBytes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            source: values.decode(RecordingSource.self, forKey: .source),
            dimensions: values.decode(RecordingDimensions.self, forKey: .dimensions),
            frameRate: values.decode(RecordingFrameRate.self, forKey: .frameRate),
            cursorMode: values.decode(RecordingCursorMode.self, forKey: .cursorMode),
            audio: values.decode(RecordingAudioConfiguration.self, forKey: .audio),
            webcam: values.decodeIfPresent(RecordingWebcamConfiguration.self, forKey: .webcam),
            countdown: values.decode(RecordingCountdown.self, forKey: .countdown),
            events: values.decode(RecordingEventConfiguration.self, forKey: .events),
            requiredSpaceEstimateBytes: values.decode(Int64.self, forKey: .requiredSpaceEstimateBytes)
        )
    }
}

nonisolated enum RecordingPermission: String, Codable, CaseIterable, Equatable, Sendable {
    case screenRecording
    case microphone
    case camera
}

nonisolated enum RecordingPermissionStatus: String, Codable, Equatable, Sendable {
    case granted
    case denied
    case restricted
    case notDetermined
}

nonisolated struct RecordingPreflightReadiness: Codable, Equatable, Sendable {
    let permissionStatuses: [RecordingPermission: RecordingPermissionStatus]
    let unavailableDeviceIDs: Set<String>
    let availableSpaceBytes: Int64

    init(
        permissionStatuses: [RecordingPermission: RecordingPermissionStatus],
        unavailableDeviceIDs: Set<String> = [],
        availableSpaceBytes: Int64
    ) {
        self.permissionStatuses = permissionStatuses
        self.unavailableDeviceIDs = unavailableDeviceIDs
        self.availableSpaceBytes = availableSpaceBytes
    }
}

nonisolated struct RecordingSessionSnapshot: Codable, Equatable, Sendable {
    let sessionID: UUID
    let configuration: RecordingSessionConfiguration
    let createdAt: Date
}

nonisolated struct RecordingCompletedOutput: Codable, Equatable, Sendable {
    let relativePath: RecordingRelativePath
    let byteCount: Int64
    let durationSeconds: Int
    let finalizedAt: Date

    init(relativePath: RecordingRelativePath, byteCount: Int64, durationSeconds: Int = 0, finalizedAt: Date) throws {
        guard byteCount > 0 else { throw RecordingSessionModelError.invalidOutputByteCount }
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.durationSeconds = max(durationSeconds, 0)
        self.finalizedAt = finalizedAt
    }
}

nonisolated enum RecordingSessionFailure: Error, Codable, Equatable, Sendable {
    case permissionUnavailable(permission: RecordingPermission, status: RecordingPermissionStatus)
    case deviceUnavailable(id: String)
    case insufficientSpace(requiredBytes: Int64, availableBytes: Int64)
    case captureFailed(code: String)
    case finalizationNotDurable
}

nonisolated enum RecordingSessionState: Equatable, Sendable {
    case idle
    case preflighting(RecordingSessionSnapshot)
    case countdown(RecordingSessionSnapshot, remainingSeconds: Int)
    case recording(RecordingSessionSnapshot)
    case paused(RecordingSessionSnapshot)
    case stopping(RecordingSessionSnapshot)
    case completed(RecordingCompletedOutput)
    case cancelled
    case failed(RecordingSessionFailure)
    case recoverableInterruption(RecordingRecoveryManifest)

    var name: String {
        switch self {
        case .idle: "idle"
        case .preflighting: "preflighting"
        case .countdown: "countdown"
        case .recording: "recording"
        case .paused: "paused"
        case .stopping: "stopping"
        case .completed: "completed"
        case .cancelled: "cancelled"
        case .failed: "failed"
        case .recoverableInterruption: "recoverableInterruption"
        }
    }
}

nonisolated enum RecordingSessionEvent: Sendable {
    case beginPreflight(configuration: RecordingSessionConfiguration, sessionID: UUID, at: Date)
    case resolvePreflight(RecordingPreflightReadiness)
    case countdownTick
    case pause
    case resume
    case stop
    case finalize(output: RecordingCompletedOutput, isDurable: Bool)
    case interrupt(RecordingRecoveryManifest)
    case recover
    case cancel
    case fail(RecordingSessionFailure)
}

nonisolated enum RecordingSessionEffect: Equatable, Sendable {
    case none
    case runPreflight
    case scheduleCountdownTick
    case beginCapture
    case pauseCapture
    case resumeCapture
    case finalizeDurably
    case preserveRecoverableArtifacts
    case discardTransientArtifacts
    case loadRecoverableArtifacts
}

nonisolated enum RecordingSessionTransitionError: Error, Equatable {
    case invalidTransition(event: String, state: String)
    case recoverySessionMismatch
}
