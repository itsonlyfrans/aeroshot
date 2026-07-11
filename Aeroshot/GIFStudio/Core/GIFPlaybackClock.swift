import Foundation

nonisolated enum GIFPlaybackRate: String, CaseIterable, Equatable, Sendable, Identifiable {
    case half, one, double

    var id: String { rawValue }
    var label: String { switch self { case .half: "0.5×"; case .one: "1×"; case .double: "2×" } }

    func contentMicroseconds(forWallMicroseconds value: Int64) -> Int64 {
        let value = max(0, value)
        switch self {
        case .half: return value / 2
        case .one: return value
        case .double:
            let (result, overflow) = value.multipliedReportingOverflow(by: 2)
            return overflow ? Int64.max : result
        }
    }

    func wallMicroseconds(forContentMicroseconds value: Int64) -> Int64 {
        let value = max(0, value)
        switch self {
        case .half:
            let (result, overflow) = value.multipliedReportingOverflow(by: 2)
            return overflow ? Int64.max : result
        case .one: return value
        case .double: return value / 2 + value % 2
        }
    }
}

/// The single presentation sequence used by preview and export.
nonisolated struct GIFPresentationPlan: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let sourceIndex: Int
        let sourceStartMicroseconds: Int64
        let durationMicroseconds: Int64
        let endMicroseconds: Int64
    }

    let entries: [Entry]
    let durationMicroseconds: Int64

    init(durations: [Int64], pingPong: Bool) throws {
        guard !durations.isEmpty else { throw GIFCoreError.noFrames }
        guard durations.allSatisfy({ $0 > 0 }) else { throw GIFCoreError.invalidDuration }
        var indices = Array(durations.indices)
        if pingPong, durations.count > 2 {
            indices += stride(from: durations.count - 2, through: 1, by: -1)
        }
        var cursor: Int64 = 0
        var sourceStarts: [Int64] = []
        var sourceCursor: Int64 = 0
        for duration in durations {
            sourceStarts.append(sourceCursor)
            let (next, overflow) = sourceCursor.addingReportingOverflow(duration)
            guard !overflow else { throw GIFCoreError.invalidDuration }
            sourceCursor = next
        }
        var result: [Entry] = []
        result.reserveCapacity(indices.count)
        for index in indices {
            let (end, overflow) = cursor.addingReportingOverflow(durations[index])
            guard !overflow else { throw GIFCoreError.invalidDuration }
            result.append(.init(
                sourceIndex: index,
                sourceStartMicroseconds: sourceStarts[index],
                durationMicroseconds: durations[index],
                endMicroseconds: end
            ))
            cursor = end
        }
        entries = result
        durationMicroseconds = cursor
    }
}

/// Pure scheduler. The caller supplies monotonic elapsed wall time; no timer is owned here.
nonisolated struct GIFPlaybackClock: Equatable, Sendable {
    struct Sample: Equatable, Sendable {
        let presentationIndex: Int
        let frameIndex: Int
        let cycleElapsedMicroseconds: Int64
        let frameElapsedMicroseconds: Int64
        let completedCycles: Int64
        let isFinished: Bool
        let contentMicrosecondsUntilNextBoundary: Int64?
    }

    let plan: GIFPresentationPlan
    let rate: GIFPlaybackRate
    let loop: GIFLoop

    init(durations: [Int64], rate: GIFPlaybackRate = .one, pingPong: Bool, loop: GIFLoop) throws {
        plan = try GIFPresentationPlan(durations: durations, pingPong: pingPong)
        self.rate = rate
        self.loop = loop
    }

    func sample(wallElapsedMicroseconds: Int64) -> Sample {
        sample(contentElapsedMicroseconds: rate.contentMicroseconds(forWallMicroseconds: wallElapsedMicroseconds))
    }

    func sample(contentElapsedMicroseconds: Int64) -> Sample {
        let contentElapsed = max(0, contentElapsedMicroseconds)
        let completed = contentElapsed / plan.durationMicroseconds
        let allowedCycles: Int64? = switch loop {
        case .once: 1
        case .count(let count): Int64(max(1, count))
        case .forever: nil
        }
        if let allowedCycles, completed >= allowedCycles {
            let lastIndex = plan.entries.count - 1
            let last = plan.entries[lastIndex]
            return .init(
                presentationIndex: lastIndex,
                frameIndex: last.sourceIndex,
                cycleElapsedMicroseconds: plan.durationMicroseconds,
                frameElapsedMicroseconds: last.durationMicroseconds,
                completedCycles: allowedCycles,
                isFinished: true,
                contentMicrosecondsUntilNextBoundary: nil
            )
        }

        let cycleElapsed = contentElapsed % plan.durationMicroseconds
        let presentationIndex = plan.entries.firstIndex { cycleElapsed < $0.endMicroseconds } ?? (plan.entries.count - 1)
        let entry = plan.entries[presentationIndex]
        let start = presentationIndex == 0 ? 0 : plan.entries[presentationIndex - 1].endMicroseconds
        return .init(
            presentationIndex: presentationIndex,
            frameIndex: entry.sourceIndex,
            cycleElapsedMicroseconds: cycleElapsed,
            frameElapsedMicroseconds: cycleElapsed - start,
            completedCycles: completed,
            isFinished: false,
            contentMicrosecondsUntilNextBoundary: entry.endMicroseconds - cycleElapsed
        )
    }
}
