import AppKit
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
    private var timer: Timer?
    private(set) var events: [RecordedEffectEvent] = []
    private let maximumEvents = 18_000

    init(startedAt: Date, normalize: @escaping (CGPoint) -> CGPoint?) {
        self.startedAt = startedAt
        self.normalize = normalize
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.record(.cursor, at: NSEvent.mouseLocation) }
        }
    }

    func recordClick(at point: CGPoint) { record(.click, at: point) }

    func stopAndWrite(beside mediaURL: URL) {
        timer?.invalidate(); timer = nil
        let sidecar = RecordingEffectSidecar(events: events)
        let url = Self.sidecarURL(for: mediaURL)
        if let data = try? JSONEncoder().encode(sidecar) { try? data.write(to: url, options: .atomic) }
    }

    nonisolated static func sidecarURL(for mediaURL: URL) -> URL {
        mediaURL.deletingPathExtension().appendingPathExtension("effects.json")
    }

    private func record(_ kind: RecordedEffectKind, at point: CGPoint) {
        guard events.count < maximumEvents, let normalized = normalize(point),
              (0...1).contains(normalized.x), (0...1).contains(normalized.y) else { return }
        events.append(.init(kind: kind, timeMicroseconds: max(0, Int64(Date().timeIntervalSince(startedAt) * 1_000_000)),
                            x: normalized.x, y: normalized.y))
    }
}
