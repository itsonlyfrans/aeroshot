import Foundation
import CoreMedia
import Testing
@testable import Aeroshot

@MainActor
struct RecordingEffectEventTests {
    @Test func sidecarIsBoundedNormalizedAndContentFree() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "EffectEvents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appending(path: "capture.mp4")
        let timeline = startedTimeline()
        let recorder = RecordingEffectEventRecorder(timeline: timeline) { point in
            guard point.x >= 0, point.y >= 0 else { return nil }
            return point
        }
        recorder.recordClick(at: CGPoint(x: 0.25, y: 0.75))
        recorder.recordClick(at: CGPoint(x: -1, y: 0))
        try recorder.stopAndWrite(beside: media)
        let data = try Data(contentsOf: RecordingEffectEventRecorder.sidecarURL(for: media))
        let decoded = try JSONDecoder().decode(RecordingEffectSidecar.self, from: data)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.events.count == 1)
        #expect(decoded.events[0].kind == .click)
        #expect(decoded.events[0].x == 0.25)
        #expect(!String(data: data, encoding: .utf8)!.contains(root.path))
    }

    @Test func invalidEffectCoordinatesFailModelValidation() {
        var model = MediaCompositionModel(assets: [], slices: [])
        model.effects.events = [.init(kind: .cursor, timeMicroseconds: 0, x: 2, y: 0)]
        #expect(model.validate().contains(.invalidEffectEvent))
    }

    @Test func effectsUseTheVideoTimelineAcrossDelayedStartupAndRepeatedPauses() {
        let timeline = RecordingMediaTimeline()
        observeVideo(timeline, 10_000)
        let recorder = RecordingEffectEventRecorder(timeline: timeline) { $0 }

        observeVideo(timeline, 11_000)
        recorder.recordClick(at: .init(x: 0.1, y: 0.1))
        _ = timeline.pause(at: time(13_000))
        recorder.pause()
        recorder.recordClick(at: .init(x: 0.2, y: 0.2))
        _ = timeline.resume(at: time(20_000))
        recorder.resume()
        observeVideo(timeline, 21_000)
        recorder.recordClick(at: .init(x: 0.3, y: 0.3))

        _ = timeline.pause(at: time(22_000))
        recorder.pause()
        _ = timeline.resume(at: time(25_000))
        recorder.resume()
        observeVideo(timeline, 26_000)
        recorder.recordClick(at: .init(x: 0.4, y: 0.4))

        #expect(recorder.events.map(\.timeMicroseconds) == [1_000_000, 4_000_000, 6_000_000])
    }

    @Test func samplingStopsAndRestartsOnlyForValidTimelineTransitions() {
        let timeline = startedTimeline()
        let recorder = RecordingEffectEventRecorder(timeline: timeline) { $0 }

        recorder.start()
        #expect(recorder.isSampling)
        recorder.resume()
        #expect(recorder.isSampling)
        recorder.pause()
        #expect(!recorder.isSampling)
        recorder.pause()
        #expect(!recorder.isSampling)
        recorder.resume()
        #expect(recorder.isSampling)
        recorder.resume()
        #expect(recorder.isSampling)
        recorder.stop()
    }

    @Test func sidecarWriteFailurePreservesMediaAndReturnsTypedError() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "EffectEvents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appending(path: "capture.mp4")
        try Data("video".utf8).write(to: media)
        let recorder = RecordingEffectEventRecorder(
            timeline: startedTimeline(),
            normalize: { $0 },
            writeSidecar: { _, _ in throw CocoaError(.fileWriteNoPermission) }
        )

        #expect(throws: RecordingEffectEventRecorderError.sidecarWriteFailed) {
            try recorder.stopAndWrite(beside: media)
        }
        #expect(FileManager.default.fileExists(atPath: media.path))
    }

    private func startedTimeline() -> RecordingMediaTimeline {
        let timeline = RecordingMediaTimeline()
        observeVideo(timeline, 10_000)
        return timeline
    }

    private func observeVideo(_ timeline: RecordingMediaTimeline, _ milliseconds: Int64) {
        let value = time(milliseconds)
        timeline.observe(value)
        _ = timeline.correctedTime(for: value, track: .video)
    }

    private func time(_ milliseconds: Int64) -> CMTime {
        CMTime(value: milliseconds, timescale: 1_000)
    }
}
