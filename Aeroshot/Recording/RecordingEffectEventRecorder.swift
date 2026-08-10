import AppKit
import CoreMedia
import Foundation

nonisolated struct RecordingEffectSidecar: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    var schemaVersion = Self.schemaVersion
    var events: [RecordedEffectEvent]
}

@MainActor
final class RecordingEffectEventRecorder {
    private let startedAt: Date
    private let normalize: (CGPoint) -> CGPoint?
    private let now: () -> Date
    private var timelineClock = RecordingTimelineClock()
    private var timer: Timer?
    var isSampling: Bool { timer != nil }
    private(set) var events: [RecordedEffectEvent] = []
    private let maximumEvents = 18_000

    init(startedAt: Date, now: @escaping () -> Date = Date.init, normalize: @escaping (CGPoint) -> CGPoint?) {
        self.startedAt = startedAt
        self.now = now
        self.normalize = normalize
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.record(.cursor, at: NSEvent.mouseLocation) }
        }
    }

    func recordClick(at point: CGPoint) { record(.click, at: point) }

    func pause() {
        if timelineClock.pause(at: sourceTime) { stop() }
    }

    func resume() {
        if timelineClock.resume(at: sourceTime) { start() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func stopAndWrite(beside mediaURL: URL) {
        stop()
        let sidecar = RecordingEffectSidecar(events: events)
        let url = Self.sidecarURL(for: mediaURL)
        if let data = try? JSONEncoder().encode(sidecar) { try? data.write(to: url, options: .atomic) }
    }

    nonisolated static func sidecarURL(for mediaURL: URL) -> URL {
        mediaURL.deletingPathExtension().appendingPathExtension("effects.json")
    }

    private func record(_ kind: RecordedEffectKind, at point: CGPoint) {
        guard events.count < maximumEvents, let normalized = normalize(point),
              (0...1).contains(normalized.x), (0...1).contains(normalized.y),
              let timestamp = timelineClock.correctedTime(for: sourceTime, track: .video) else { return }
        events.append(.init(kind: kind, timeMicroseconds: max(0, timestamp.convertScale(1_000_000, method: .roundTowardZero).value),
                            x: normalized.x, y: normalized.y))
    }

    private var sourceTime: CMTime {
        CMTime(seconds: now().timeIntervalSince(startedAt), preferredTimescale: 1_000_000)
    }
}
