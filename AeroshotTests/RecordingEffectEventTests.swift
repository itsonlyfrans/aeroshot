import Foundation
import Testing
@testable import Aeroshot

@MainActor
struct RecordingEffectEventTests {
    @Test func sidecarIsBoundedNormalizedAndContentFree() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "EffectEvents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appending(path: "capture.mp4")
        let recorder = RecordingEffectEventRecorder(startedAt: Date()) { point in
            guard point.x >= 0, point.y >= 0 else { return nil }
            return point
        }
        recorder.recordClick(at: CGPoint(x: 0.25, y: 0.75))
        recorder.recordClick(at: CGPoint(x: -1, y: 0))
        recorder.stopAndWrite(beside: media)
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

    @Test func effectsUseThePauseStrippedRecordingTimeline() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        var now = startedAt
        let recorder = RecordingEffectEventRecorder(startedAt: startedAt, now: { now }) { $0 }

        now.addTimeInterval(1)
        recorder.recordClick(at: .init(x: 0.1, y: 0.1))
        now.addTimeInterval(2)
        recorder.pause()
        now.addTimeInterval(7)
        recorder.recordClick(at: .init(x: 0.2, y: 0.2))
        recorder.resume()
        now.addTimeInterval(1)
        recorder.recordClick(at: .init(x: 0.3, y: 0.3))

        #expect(recorder.events.map(\.timeMicroseconds) == [1_000_000, 4_000_000])
    }

    @Test func samplingStopsAndRestartsOnlyForValidTimelineTransitions() {
        let recorder = RecordingEffectEventRecorder(startedAt: Date()) { $0 }

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
}
