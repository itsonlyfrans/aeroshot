import AppKit
import CoreMedia
import Foundation

nonisolated struct RecordingEffectSidecar: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    var schemaVersion = Self.schemaVersion
    var events: [RecordedEffectEvent]
}

nonisolated enum RecordingEffectEventRecorderError: LocalizedError, Equatable {
    case sidecarWriteFailed

    var errorDescription: String? {
        "The video was saved, but recording effects could not be saved."
    }
}

@MainActor
final class RecordingEffectEventRecorder {
    private let normalize: (CGPoint) -> CGPoint?
    private let timeline: RecordingMediaTimeline
    private let writeSidecar: (Data, URL) throws -> Void
    private var timer: Timer?
    var isSampling: Bool { timer != nil }
    private(set) var events: [RecordedEffectEvent] = []
    private let maximumEvents = 18_000

    init(
        timeline: RecordingMediaTimeline,
        normalize: @escaping (CGPoint) -> CGPoint?,
        writeSidecar: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.timeline = timeline
        self.normalize = normalize
        self.writeSidecar = writeSidecar
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.record(.cursor, at: NSEvent.mouseLocation) }
        }
    }

    func recordClick(at point: CGPoint) { record(.click, at: point) }

    func pause() { stop() }

    func resume() {
        guard !timeline.isPaused else { return }
        start()
    }

    func stop() { timer?.invalidate(); timer = nil }

    func stopAndWrite(beside mediaURL: URL) throws {
        stop()
        let sidecar = RecordingEffectSidecar(events: events)
        let url = Self.sidecarURL(for: mediaURL)
        do {
            try writeSidecar(JSONEncoder().encode(sidecar), url)
        } catch {
            throw RecordingEffectEventRecorderError.sidecarWriteFailed
        }
    }

    nonisolated static func sidecarURL(for mediaURL: URL) -> URL {
        mediaURL.deletingPathExtension().appendingPathExtension("effects.json")
    }

    private func record(_ kind: RecordedEffectKind, at point: CGPoint) {
        guard events.count < maximumEvents, let normalized = normalize(point),
              (0...1).contains(normalized.x), (0...1).contains(normalized.y),
              let timestamp = timeline.currentEffectTime() else { return }
        events.append(.init(kind: kind, timeMicroseconds: max(0, timestamp.convertScale(1_000_000, method: .roundTowardZero).value),
                            x: normalized.x, y: normalized.y))
    }
}
