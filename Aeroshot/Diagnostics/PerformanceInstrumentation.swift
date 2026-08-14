import OSLog
import os

nonisolated enum PerformanceSampleKind: Sendable {
    case video
    case systemAudio
    case microphone
    case gif
}

nonisolated struct PerformanceCounterSnapshot: Equatable, Sendable {
    var arrivedSamples = 0
    var appendedSamples = 0
    var droppedSamples = 0
    var backpressureDroppedSamples = 0
    var incompleteSamples = 0
    var pausedSamples = 0
    var pendingVideoBuffers = 0
    var pendingSystemAudioBuffers = 0
    var pendingMicrophoneBuffers = 0
    var scratchBytes: Int64 = 0
    var firstTerminalError: String?

    var pendingAudioBuffers: Int { pendingSystemAudioBuffers + pendingMicrophoneBuffers }
}

/// Content-free, process-local counters for Instruments and release tests.
nonisolated final class PerformanceCounters: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: PerformanceCounterSnapshot())

    var snapshot: PerformanceCounterSnapshot { state.withLock { $0 } }

    func reset() {
        state.withLock { $0 = PerformanceCounterSnapshot() }
    }

    func recordArrival(_ kind: PerformanceSampleKind) {
        _ = reservePending(kind, limit: .max)
    }

    @discardableResult
    func reservePending(_ kind: PerformanceSampleKind, limit: Int) -> Bool {
        state.withLock {
            $0.arrivedSamples += 1
            switch kind {
            case .video:
                guard $0.pendingVideoBuffers < limit else {
                    $0.droppedSamples += 1
                    $0.backpressureDroppedSamples += 1
                    return false
                }
                $0.pendingVideoBuffers += 1
            case .systemAudio:
                guard $0.pendingSystemAudioBuffers < limit else {
                    $0.droppedSamples += 1
                    $0.backpressureDroppedSamples += 1
                    return false
                }
                $0.pendingSystemAudioBuffers += 1
            case .microphone:
                guard $0.pendingMicrophoneBuffers < limit else {
                    $0.droppedSamples += 1
                    $0.backpressureDroppedSamples += 1
                    return false
                }
                $0.pendingMicrophoneBuffers += 1
            case .gif:
                break
            }
            return true
        }
    }

    func recordIncompleteSample() { state.withLock { $0.incompleteSamples += 1 } }

    func recordPausedSample() { state.withLock { $0.pausedSamples += 1 } }

    func recordCompletion(
        _ kind: PerformanceSampleKind,
        appended: Bool,
        backpressure: Bool = false,
        terminalError: String? = nil
    ) {
        state.withLock {
            if appended { $0.appendedSamples += 1 } else { $0.droppedSamples += 1 }
            if backpressure { $0.backpressureDroppedSamples += 1 }
            switch kind {
            case .video: $0.pendingVideoBuffers = max(0, $0.pendingVideoBuffers - 1)
            case .systemAudio: $0.pendingSystemAudioBuffers = max(0, $0.pendingSystemAudioBuffers - 1)
            case .microphone: $0.pendingMicrophoneBuffers = max(0, $0.pendingMicrophoneBuffers - 1)
            case .gif: break
            }
            if $0.firstTerminalError == nil { $0.firstTerminalError = terminalError }
        }
    }

    func setScratchBytes(_ byteCount: Int64) {
        state.withLock { $0.scratchBytes = max(0, byteCount) }
    }

    func recordTerminalError(_ error: Error) {
        state.withLock {
            if $0.firstTerminalError == nil { $0.firstTerminalError = error.localizedDescription }
        }
    }
}

nonisolated enum PerformanceInstrumentation {
    static let signposter = OSSignposter(subsystem: "com.aeroshot", category: "Performance")
    static let counters = PerformanceCounters()
}
