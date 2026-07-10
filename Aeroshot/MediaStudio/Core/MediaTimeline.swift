import Foundation

nonisolated enum MediaTimelineError: Error, Equatable {
    case invalidModel([MediaModelValidationError])
    case rangeOutsideComposition
    case selectionOutsideFirstSlice
}

nonisolated extension MediaCompositionModel {
    func split(at compositionTime: RationalTime) throws -> Self {
        try requireValidTimeline()
        guard compositionTime >= .zero, compositionTime <= duration else { throw MediaTimelineError.rangeOutsideComposition }
        guard compositionTime > .zero, compositionTime < duration else { return self }

        var cursor = RationalTime.zero
        var result: [MediaSlice] = []
        for slice in slices {
            let sliceEnd = try cursor + slice.sourceRange.duration
            if compositionTime > cursor, compositionTime < sliceEnd {
                let leftDuration = try compositionTime - cursor
                let rightStart = try slice.sourceRange.start + leftDuration
                let rightDuration = try slice.sourceRange.duration - leftDuration
                result.append(MediaSlice(sourceAssetID: slice.sourceAssetID, sourceRange: .init(start: slice.sourceRange.start, duration: leftDuration)))
                result.append(MediaSlice(sourceAssetID: slice.sourceAssetID, sourceRange: .init(start: rightStart, duration: rightDuration)))
            } else {
                result.append(slice)
            }
            cursor = sliceEnd
        }
        var copy = self
        copy.slices = result
        return copy
    }

    /// Retains a composition range and moves its first retained sample to time zero.
    func trim(to range: RationalTimeRange) throws -> Self {
        try requireValidTimeline()
        guard range.start >= .zero, range.duration >= .zero, range.end <= duration else {
            throw MediaTimelineError.rangeOutsideComposition
        }
        var copy = self
        guard !range.isEmpty else { copy.slices = []; copy.overlays = []; return copy }

        var cursor = RationalTime.zero
        copy.slices = try slices.compactMap { slice in
            let compositionRange = RationalTimeRange(start: cursor, duration: slice.sourceRange.duration)
            defer { cursor = compositionRange.end }
            guard let retained = compositionRange.intersection(range) else { return nil }
            let sourceOffset = try retained.start - compositionRange.start
            let sourceStart = try slice.sourceRange.start + sourceOffset
            return MediaSlice(sourceAssetID: slice.sourceAssetID, sourceRange: .init(start: sourceStart, duration: retained.duration))
        }
        copy.overlays = overlays.compactMap { overlay in
            guard let retained = overlay.range.intersection(range),
                  let shifted = try? retained.start - range.start else { return nil }
            var value = overlay
            value.range = .init(start: shifted, duration: retained.duration)
            return value
        }
        return copy
    }

    /// Removes a range wholly inside the first slice. Later slices close toward
    /// zero, but arbitrary multi-slice ripple editing is intentionally unsupported.
    func deleteSelectedRange(_ range: RationalTimeRange) throws -> Self {
        try requireValidTimeline()
        guard range.start >= .zero, range.duration >= .zero else { throw MediaTimelineError.rangeOutsideComposition }
        guard !range.isEmpty else { return self }
        guard let first = slices.first, range.end <= first.sourceRange.duration else {
            throw MediaTimelineError.selectionOutsideFirstSlice
        }

        var replacement: [MediaSlice] = []
        if range.start > .zero {
            replacement.append(MediaSlice(sourceAssetID: first.sourceAssetID, sourceRange: .init(start: first.sourceRange.start, duration: range.start)))
        }
        let trailingDuration = try first.sourceRange.duration - range.end
        if trailingDuration > .zero {
            replacement.append(MediaSlice(
                sourceAssetID: first.sourceAssetID,
                sourceRange: .init(start: try first.sourceRange.start + range.end, duration: trailingDuration)
            ))
        }
        var copy = self
        copy.slices = replacement + slices.dropFirst()
        copy.overlays = overlays.compactMap { overlay in
            if overlay.range.end <= range.start { return overlay }
            if overlay.range.start >= range.end {
                var shifted = overlay
                shifted.range.start = (try? overlay.range.start - range.duration) ?? overlay.range.start
                return shifted
            }
            // A range crossing the cut retains its visible portions as one range.
            let visibleBefore = max(RationalTime.zero, (try? range.start - overlay.range.start) ?? .zero)
            let visibleAfter = max(RationalTime.zero, (try? overlay.range.end - range.end) ?? .zero)
            guard let retainedDuration = try? visibleBefore + visibleAfter, retainedDuration > .zero else { return nil }
            var retained = overlay
            retained.range.start = min(overlay.range.start, range.start)
            retained.range.duration = retainedDuration
            return retained
        }
        return copy
    }

    func sourcePosition(at compositionTime: RationalTime) -> SourcePosition? {
        guard compositionTime >= .zero, compositionTime < duration else { return nil }
        var cursor = RationalTime.zero
        for slice in slices {
            let end = (try? cursor + slice.sourceRange.duration) ?? cursor
            if compositionTime >= cursor, compositionTime < end,
               let offset = try? compositionTime - cursor,
               let sourceTime = try? slice.sourceRange.start + offset {
                return SourcePosition(assetID: slice.sourceAssetID, time: sourceTime)
            }
            cursor = end
        }
        return nil
    }

    /// Returns the earliest composition occurrence when a source sample appears
    /// more than once.
    func compositionTime(for source: SourcePosition) -> RationalTime? {
        var cursor = RationalTime.zero
        for slice in slices {
            if slice.sourceAssetID == source.assetID, slice.sourceRange.contains(source.time),
               let offset = try? source.time - slice.sourceRange.start {
                return try? cursor + offset
            }
            cursor = (try? cursor + slice.sourceRange.duration) ?? cursor
        }
        return nil
    }

    private func requireValidTimeline() throws {
        let errors = validate().filter {
            switch $0 {
            case .invalidOverlayRange, .invalidCrop, .invalidCanvas, .invalidAudioGain: false
            default: true
            }
        }
        if !errors.isEmpty { throw MediaTimelineError.invalidModel(errors) }
    }
}
