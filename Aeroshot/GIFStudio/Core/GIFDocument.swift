import CoreGraphics
import Foundation

nonisolated enum GIFLoop: Codable, Equatable, Sendable {
    case once
    case count(Int)
    case forever

    var imageIOLoopCount: Int {
        switch self {
        case .once: 1
        case .count(let count): max(1, count)
        case .forever: 0
        }
    }
}

nonisolated enum GIFDither: String, Codable, CaseIterable, Sendable {
    case none
    case ordered
}

nonisolated enum GIFExportPreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case documentation, social
    var id: String { rawValue }
    var displayName: String { self == .documentation ? "Documentation" : "Social" }

    func applying(to current: GIFExportSettings) -> GIFExportSettings {
        var result = current
        switch self {
        case .documentation:
            result.paletteSize = 128
            result.dither = .none
            result.preservesTransparency = true
            result.quality = 0.9
        case .social:
            result.outputWidth = min(current.outputWidth ?? 1_280, 1_280)
            result.paletteSize = 64
            result.dither = .ordered
            result.preservesTransparency = false
            result.quality = 0.7
        }
        return result
    }
}

nonisolated struct GIFExportSettings: Codable, Equatable, Sendable {
    var loop: GIFLoop = .forever
    var pingPong = false
    var outputWidth: Int?
    var outputHeight: Int?
    var paletteSize = 256
    var dither: GIFDither = .none
    var preservesTransparency = true
    var quality = 1.0

    func validated() throws -> Self {
        guard (2...256).contains(paletteSize), (0...1).contains(quality) else {
            throw GIFCoreError.invalidSettings
        }
        if let outputWidth, outputWidth <= 0 { throw GIFCoreError.invalidSettings }
        if let outputHeight, outputHeight <= 0 { throw GIFCoreError.invalidSettings }
        if case .count(let count) = loop, count < 1 { throw GIFCoreError.invalidSettings }
        return self
    }
}

nonisolated struct GIFFrame: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var sourceURL: URL
    /// Exact source duration. Integer microseconds avoid binary floating-point edit drift.
    var durationMicroseconds: Int64

    init(id: UUID = UUID(), sourceURL: URL, durationMicroseconds: Int64) throws {
        guard durationMicroseconds > 0 else { throw GIFCoreError.invalidDuration }
        self.id = id
        self.sourceURL = sourceURL
        self.durationMicroseconds = durationMicroseconds
    }
}

nonisolated struct GIFTimeRange: Codable, Equatable, Sendable {
    var startMicroseconds: Int64
    var durationMicroseconds: Int64

    var endMicroseconds: Int64 { startMicroseconds + durationMicroseconds }

    init(startMicroseconds: Int64, durationMicroseconds: Int64) throws {
        guard startMicroseconds >= 0, durationMicroseconds > 0,
              startMicroseconds <= Int64.max - durationMicroseconds else { throw GIFCoreError.invalidRange }
        self.startMicroseconds = startMicroseconds
        self.durationMicroseconds = durationMicroseconds
    }
}

nonisolated struct GIFDocument: Codable, Equatable, Sendable {
    var frames: [GIFFrame]
    var settings: GIFExportSettings

    init(frames: [GIFFrame], settings: GIFExportSettings = .init()) throws {
        guard !frames.isEmpty else { throw GIFCoreError.noFrames }
        guard frames.allSatisfy({ $0.durationMicroseconds > 0 }) else { throw GIFCoreError.invalidDuration }
        self.frames = frames
        self.settings = try settings.validated()
    }

    var durationMicroseconds: Int64 { frames.reduce(0) { $0 + $1.durationMicroseconds } }

    func trimmed(to range: Range<Int>) throws -> Self {
        guard range.lowerBound >= 0, range.upperBound <= frames.count, !range.isEmpty else {
            throw GIFCoreError.invalidRange
        }
        return try Self(frames: Array(frames[range]), settings: settings)
    }

    func split(at index: Int) throws -> (Self, Self) {
        guard index > 0, index < frames.count else { throw GIFCoreError.invalidRange }
        return (
            try Self(frames: Array(frames[..<index]), settings: settings),
            try Self(frames: Array(frames[index...]), settings: settings)
        )
    }

    func timeRange(forFrameAt index: Int) throws -> GIFTimeRange {
        guard frames.indices.contains(index) else { throw GIFCoreError.invalidRange }
        let start = frames[..<index].reduce(0) { $0 + $1.durationMicroseconds }
        return try GIFTimeRange(startMicroseconds: start, durationMicroseconds: frames[index].durationMicroseconds)
    }

    func trimmed(to range: GIFTimeRange) throws -> Self {
        guard range.endMicroseconds <= durationMicroseconds else { throw GIFCoreError.invalidRange }
        let selected = try slices(intersecting: range)
        return try Self(frames: selected, settings: settings)
    }

    func split(atMicroseconds time: Int64) throws -> (Self, Self) {
        guard time > 0, time < durationMicroseconds else { throw GIFCoreError.invalidRange }
        return (
            try trimmed(to: GIFTimeRange(startMicroseconds: 0, durationMicroseconds: time)),
            try trimmed(to: GIFTimeRange(startMicroseconds: time, durationMicroseconds: durationMicroseconds - time))
        )
    }

    mutating func delete(_ range: GIFTimeRange) throws {
        guard range.endMicroseconds <= durationMicroseconds, range.durationMicroseconds < durationMicroseconds else {
            throw GIFCoreError.invalidRange
        }
        var remaining: [GIFFrame] = []
        if range.startMicroseconds > 0 {
            remaining += try slices(intersecting: GIFTimeRange(startMicroseconds: 0, durationMicroseconds: range.startMicroseconds))
        }
        if range.endMicroseconds < durationMicroseconds {
            remaining += try slices(intersecting: GIFTimeRange(
                startMicroseconds: range.endMicroseconds,
                durationMicroseconds: durationMicroseconds - range.endMicroseconds
            ))
        }
        frames = remaining
    }

    mutating func delete(_ range: Range<Int>) throws {
        guard range.lowerBound >= 0, range.upperBound <= frames.count, !range.isEmpty,
              range.count < frames.count else { throw GIFCoreError.invalidRange }
        frames.removeSubrange(range)
    }

    mutating func deleteFrame(at index: Int) throws { try delete(index..<(index + 1)) }

    mutating func duplicateFrame(at index: Int) throws {
        guard frames.indices.contains(index) else { throw GIFCoreError.invalidRange }
        var copy = frames[index]
        copy = try GIFFrame(sourceURL: copy.sourceURL, durationMicroseconds: copy.durationMicroseconds)
        frames.insert(copy, at: index + 1)
    }

    mutating func setDuration(_ durationMicroseconds: Int64, for range: Range<Int>) throws {
        guard durationMicroseconds > 0, range.lowerBound >= 0, range.upperBound <= frames.count,
              !range.isEmpty else { throw GIFCoreError.invalidRange }
        for index in range { frames[index].durationMicroseconds = durationMicroseconds }
    }

    /// A deterministic, conservative estimate intended for UI guidance, not a promised byte count.
    func estimatedOutputBytes(sourceSize: CGSize) -> Int64 {
        let width = max(1, settings.outputWidth ?? Int(sourceSize.width))
        let height = max(1, settings.outputHeight ?? Int(sourceSize.height))
        let bitsPerPixel = max(1, Int(ceil(log2(Double(settings.paletteSize)))))
        let uniqueFrameFactor = settings.pingPong && frames.count > 1 ? frames.count * 2 - 2 : frames.count
        let rawIndexedBytes = Int64(width * height * bitsPerPixel * uniqueFrameFactor) / 8
        let qualityFactor = 0.25 + (0.5 * settings.quality)
        return max(128, Int64(Double(rawIndexedBytes) * qualityFactor) + Int64(uniqueFrameFactor * 32))
    }


    private func slices(intersecting selection: GIFTimeRange) throws -> [GIFFrame] {
        var cursor: Int64 = 0
        var result: [GIFFrame] = []
        for frame in frames {
            let frameEnd = cursor + frame.durationMicroseconds
            let overlapStart = max(cursor, selection.startMicroseconds)
            let overlapEnd = min(frameEnd, selection.endMicroseconds)
            if overlapEnd > overlapStart {
                result.append(try GIFFrame(
                    sourceURL: frame.sourceURL,
                    durationMicroseconds: overlapEnd - overlapStart
                ))
            }
            cursor = frameEnd
        }
        guard !result.isEmpty else { throw GIFCoreError.invalidRange }
        return result
    }
}

nonisolated enum GIFCoreError: Error, Equatable {
    case noFrames
    case invalidDuration
    case invalidRange
    case invalidSettings
    case imageReadFailed
    case imageWriteFailed
    case cancelled
}
