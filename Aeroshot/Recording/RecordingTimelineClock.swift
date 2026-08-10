import CoreMedia

/// Thread-safe capture timebase shared by encoded media and recorded effects.
nonisolated final class RecordingMediaTimeline: @unchecked Sendable {
    private let lock = NSLock()
    private var clock = RecordingTimelineClock()
    private var latestSourceTime: CMTime?
    private var firstVideoTime: CMTime?
    private var recordedDuration: CMTime?
    private var finalizedDuration: CMTime?

    func reset() {
        lock.lock()
        clock = RecordingTimelineClock()
        latestSourceTime = nil
        firstVideoTime = nil
        recordedDuration = nil
        finalizedDuration = nil
        lock.unlock()
    }

    func observe(_ sourceTime: CMTime) {
        guard sourceTime.isNumeric else { return }
        lock.lock()
        if latestSourceTime == nil || CMTimeCompare(sourceTime, latestSourceTime!) > 0 {
            latestSourceTime = sourceTime
        }
        lock.unlock()
    }

    func pause(at sourceTime: CMTime?) -> Bool {
        guard let sourceTime else { return false }
        lock.lock()
        defer { lock.unlock() }
        return clock.pause(at: sourceTime)
    }

    func resume(at sourceTime: CMTime) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return clock.resume(at: sourceTime)
    }

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return clock.isPaused
    }

    func correctedTime(for sourceTime: CMTime, track: RecordingTimelineClock.Track) -> CMTime? {
        lock.lock()
        defer { lock.unlock() }
        let corrected = clock.correctedTime(for: sourceTime, track: track)
        if track == .video, let corrected {
            if firstVideoTime == nil { firstVideoTime = corrected }
            if let firstVideoTime {
                recordedDuration = CMTimeMaximum(.zero, CMTimeSubtract(corrected, firstVideoTime))
            }
        }
        return corrected
    }

    /// Returns the encoded video duration. It excludes every paused interval.
    func mediaDuration() -> CMTime? {
        lock.lock()
        defer { lock.unlock() }
        return finalizedDuration ?? recordedDuration
    }

    /// Retains the final duration after the writer releases its active timebase.
    func finalize() {
        lock.lock()
        finalizedDuration = recordedDuration
        lock.unlock()
    }

    /// Uses the latest captured video time. Effects never use wall-clock time.
    func currentEffectTime() -> CMTime? {
        lock.lock()
        defer { lock.unlock() }
        guard let sourceTime = latestSourceTime,
              let firstVideoTime,
              let corrected = clock.correctedTime(for: sourceTime, track: .video)
        else { return nil }
        return CMTimeSubtract(corrected, firstVideoTime)
    }
}

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
