import CoreMedia
import Testing
@testable import Aeroshot

struct RecordingTimelineTests {
    private func time(_ value: Int64, _ timescale: Int32 = 1_000) -> CMTime {
        CMTime(value: value, timescale: timescale)
    }

    private func expectEqual(_ lhs: CMTime?, _ rhs: CMTime, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(lhs != nil, sourceLocation: sourceLocation)
        if let lhs {
            #expect(CMTimeCompare(lhs, rhs) == 0, sourceLocation: sourceLocation)
        }
    }

    @Test func multiplePausesAreRemovedExactly() {
        var clock = RecordingTimelineClock()
        expectEqual(clock.correctedTime(for: time(1_000), track: .video), time(1_000))
        let firstPause = clock.pause(at: time(2_000))
        let sampleDuringPause = clock.correctedTime(for: time(2_500), track: .video)
        let firstResume = clock.resume(at: time(5_000))
        #expect(firstPause)
        #expect(sampleDuringPause == nil)
        #expect(firstResume)
        expectEqual(clock.correctedTime(for: time(6_000), track: .video), time(3_000))

        let secondPause = clock.pause(at: time(8_000))
        let secondResume = clock.resume(at: time(8_750))
        #expect(secondPause)
        #expect(secondResume)
        expectEqual(clock.correctedTime(for: time(10_000), track: .video), time(6_250))
        expectEqual(clock.accumulatedPausedDuration, time(3_750))
    }

    @Test func sharedMediaDurationExcludesRepeatedPausesAndPersistsAtFinalization() {
        let timeline = RecordingMediaTimeline()
        _ = timeline.correctedTime(for: time(1_000), track: .video)
        _ = timeline.correctedTime(for: time(2_000), track: .video)
        #expect(timeline.pause(at: time(2_000)))
        #expect(timeline.resume(at: time(5_000)))
        _ = timeline.correctedTime(for: time(6_000), track: .video)
        _ = timeline.correctedTime(for: time(8_000), track: .video)
        #expect(timeline.pause(at: time(8_000)))
        #expect(timeline.resume(at: time(8_750)))
        _ = timeline.correctedTime(for: time(10_000), track: .video)

        expectEqual(timeline.mediaDuration(), time(5_250))
        timeline.finalize()
        expectEqual(timeline.mediaDuration(), time(5_250))
    }

    @Test func videoSystemAudioAndMicrophoneRemainAligned() {
        var clock = RecordingTimelineClock()
        let didPause = clock.pause(at: time(90_000, 48_000))
        let didResume = clock.resume(at: time(138_000, 48_000))
        #expect(didPause)
        #expect(didResume)

        let source = time(240_000, 48_000)
        let expected = time(192_000, 48_000)
        expectEqual(clock.correctedTime(for: source, track: .video), expected)
        expectEqual(clock.correctedTime(for: source, track: .systemAudio), expected)
        expectEqual(clock.correctedTime(for: source, track: .microphone), expected)
    }

    @Test func nonZeroFirstTimestampIsPreserved() {
        var clock = RecordingTimelineClock()
        expectEqual(clock.correctedTime(for: time(42_000, 600), track: .video), time(42_000, 600))
    }

    @Test func pauseBeforeFirstSampleCorrectsWithoutNormalizingOrigin() {
        var clock = RecordingTimelineClock()
        let didPause = clock.pause(at: time(10_000))
        let didResume = clock.resume(at: time(13_000))
        #expect(didPause)
        #expect(didResume)
        expectEqual(clock.correctedTime(for: time(15_000), track: .video), time(12_000))
    }

    @Test func invalidTransitionsAreIdempotent() {
        var clock = RecordingTimelineClock()
        let resumeWhileRunning = clock.resume(at: time(1_000))
        let firstPause = clock.pause(at: time(2_000))
        let repeatedPause = clock.pause(at: time(3_000))
        let backwardsResume = clock.resume(at: time(1_999))
        #expect(!resumeWhileRunning)
        #expect(firstPause)
        #expect(!repeatedPause)
        #expect(!backwardsResume)
        #expect(clock.isPaused)
        let validResume = clock.resume(at: time(4_000))
        let repeatedResume = clock.resume(at: time(5_000))
        #expect(validResume)
        #expect(!repeatedResume)
        expectEqual(clock.accumulatedPausedDuration, time(2_000))
    }

    @Test func monotonicityIsIndependentPerTrack() {
        var clock = RecordingTimelineClock()
        expectEqual(clock.correctedTime(for: time(2_000), track: .video), time(2_000))
        expectEqual(clock.correctedTime(for: time(1_900), track: .video), time(2_000))
        expectEqual(clock.correctedTime(for: time(1_950), track: .systemAudio), time(1_950))
    }

    @Test func longDurationRetainsExactRationalPrecision() {
        var clock = RecordingTimelineClock()
        let scale: Int32 = 90_000
        let hour: Int64 = 60 * 60 * Int64(scale)
        let didPause = clock.pause(at: time(12 * hour + 3_003, scale))
        let didResume = clock.resume(at: time(12 * hour + 93_093, scale))
        #expect(didPause)
        #expect(didResume)

        let source = time(72 * hour + 180_180, scale)
        let expected = time(72 * hour + 90_090, scale)
        expectEqual(clock.correctedTime(for: source, track: .video), expected)
        expectEqual(clock.correctedTime(for: source, track: .systemAudio), expected)
        expectEqual(clock.correctedTime(for: source, track: .microphone), expected)
    }
}
