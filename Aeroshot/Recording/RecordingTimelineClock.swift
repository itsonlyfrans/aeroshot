import CoreMedia

/// Pure rational-time state used to remove capture pauses from every recorded track.
nonisolated struct RecordingTimelineClock {
    enum Track: Hashable, Sendable {
        case video
        case systemAudio
        case microphone
    }

    private(set) var isPaused = false
    private(set) var accumulatedPausedDuration: CMTime = .zero
    private var pauseStartedAt: CMTime?
    private var lastCorrectedTime: [Track: CMTime] = [:]

    /// Starts a pause at a source timestamp. Repeated or invalid transitions do nothing.
    @discardableResult
    mutating func pause(at sourceTime: CMTime) -> Bool {
        guard !isPaused, sourceTime.isNumeric else { return false }
        isPaused = true
        pauseStartedAt = sourceTime
        return true
    }

    /// Ends a pause and adds its exact rational duration to the canonical correction.
    @discardableResult
    mutating func resume(at sourceTime: CMTime) -> Bool {
        guard isPaused,
              sourceTime.isNumeric,
              let pauseStartedAt,
              CMTimeCompare(sourceTime, pauseStartedAt) >= 0
        else { return false }

        accumulatedPausedDuration = CMTimeAdd(
            accumulatedPausedDuration,
            CMTimeSubtract(sourceTime, pauseStartedAt)
        )
        self.pauseStartedAt = nil
        isPaused = false
        return true
    }

    /// Returns a corrected timestamp, or nil while paused/for an invalid timestamp.
    /// Monotonicity is enforced independently per track so inter-track offsets survive.
    mutating func correctedTime(for sourceTime: CMTime, track: Track) -> CMTime? {
        guard !isPaused, sourceTime.isNumeric else { return nil }

        var corrected = CMTimeSubtract(sourceTime, accumulatedPausedDuration)
        if let last = lastCorrectedTime[track], CMTimeCompare(corrected, last) < 0 {
            corrected = last
        }
        lastCorrectedTime[track] = corrected
        return corrected
    }
}
