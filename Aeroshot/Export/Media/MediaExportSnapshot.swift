import Foundation

/// A value-only render contract captured before export starts. Preview and export
/// clients receive this same value, so neither can observe later editor changes.
nonisolated struct MediaExportSnapshot: Equatable, Sendable {
    let projectID: UUID
    let sourceURL: URL
    let sourceAsset: AeroProjectAsset
    let canvas: AeroProjectCanvas
    let timeline: [AeroTimelineItem]
    let overlays: [AeroOverlay]
    let eventTracks: [AeroEventTrack]
    let effects: PresentationEffectsState
    let webcamURL: URL?

    /// Version-1 project timelines express one source range/trim boundary.
    /// Later edit operations remain in the immutable array for a richer compiler.
    var effectiveSourceRange: AeroMediaTimeRange? {
        timeline.first {
            ($0.kind == .trim || $0.kind == .sourceRange)
                && ($0.sourceAssetID == nil || $0.sourceAssetID == sourceAsset.id)
                && $0.timeRange != nil
        }?.timeRange
    }

    init(manifest: AeroProjectManifest, packageURL: URL) throws {
        guard let sourceID = manifest.primarySourceAssetID,
              let source = manifest.assets.first(where: { $0.id == sourceID }) else {
            throw MediaExportError.missingSourceAsset
        }
        let root = packageURL.standardizedFileURL
        let candidate = root.appending(path: source.relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"), !source.relativePath.contains("..") else {
            throw MediaExportError.invalidSourcePath
        }
        projectID = manifest.id
        sourceURL = candidate
        sourceAsset = source
        canvas = manifest.canvas
        timeline = manifest.timeline
        overlays = manifest.overlays.sorted { ($0.zIndex, $0.id.uuidString) < ($1.zIndex, $1.id.uuidString) }
        eventTracks = manifest.eventTracks
        effects = manifest.mediaComposition?.effects.map {
            .init(events: $0.events.map { .init(kind: $0.kind == .cursor ? .cursor : .click,
                                                  timeMicroseconds: $0.timeMicroseconds, x: $0.x, y: $0.y) },
                  cursorEmphasis: $0.cursorEmphasis, clickEmphasis: $0.clickEmphasis,
                  freezeFrame: $0.freezeFrame, reframeAspectRatio: $0.reframeAspectRatio,
                  webcam: $0.webcam, punchInClickTimes: $0.punchInClickTimes, clickSound: $0.clickSound)
        } ?? .init()
        let webcamID = effects.webcam.sourceAssetID
            ?? manifest.assets.first { $0.id != source.id && $0.metadata.mediaType == .video }?.id
        if let webcamID, let webcam = manifest.assets.first(where: { $0.id == webcamID }) {
            let webcamCandidate = root.appending(path: webcam.relativePath).standardizedFileURL
            webcamURL = webcamCandidate.path.hasPrefix(root.path + "/") && !webcam.relativePath.contains("..")
                ? webcamCandidate : nil
        } else {
            webcamURL = nil
        }
    }

    init(
        projectID: UUID,
        sourceURL: URL,
        sourceAsset: AeroProjectAsset,
        canvas: AeroProjectCanvas,
        timeline: [AeroTimelineItem] = [],
        overlays: [AeroOverlay] = [],
        eventTracks: [AeroEventTrack] = [],
        effects: PresentationEffectsState = .init(),
        webcamURL: URL? = nil
    ) {
        self.projectID = projectID
        self.sourceURL = sourceURL
        self.sourceAsset = sourceAsset
        self.canvas = canvas
        self.timeline = timeline
        self.overlays = overlays.sorted { ($0.zIndex, $0.id.uuidString) < ($1.zIndex, $1.id.uuidString) }
        self.eventTracks = eventTracks
        self.effects = effects
        self.webcamURL = webcamURL
    }
}

/// Converts source event times to the timeline after an inserted freeze frame.
nonisolated struct MediaOutputTiming: Equatable, Sendable {
    static let cursorEmphasisDurationMicroseconds: Int64 = 160_000
    static let punchInDurationMicroseconds: Int64 = 350_000
    static let punchInScale = 1.35

    let freezeFrame: FreezeFrameEffect?

    init(freezeFrame: FreezeFrameEffect?) { self.freezeFrame = freezeFrame }

    func outputTimeMicroseconds(forSourceTime time: Int64) -> Int64 {
        guard let freezeFrame,
              time >= freezeFrame.timeMicroseconds else { return time }
        return time + freezeFrame.durationMicroseconds
    }

    /// Holds dependent source media on the freeze frame while output time advances.
    func sourceTimeMicroseconds(forOutputTime time: Int64) -> Int64 {
        guard let freezeFrame, time >= freezeFrame.timeMicroseconds else { return time }
        let resumeTime = freezeFrame.timeMicroseconds + freezeFrame.durationMicroseconds
        guard time >= resumeTime else { return freezeFrame.timeMicroseconds }
        return time - freezeFrame.durationMicroseconds
    }

    func isPunchInActive(atOutputTime outputTime: Int64, forSourceTime sourceTime: Int64) -> Bool {
        let start = outputTimeMicroseconds(forSourceTime: sourceTime)
        return outputTime >= start && outputTime < start + Self.punchInDurationMicroseconds
    }

    static func zoomedCrop(_ crop: AeroNormalizedRect, around event: RecordedEffectEvent) -> AeroNormalizedRect {
        let width = crop.width / punchInScale
        let height = crop.height / punchInScale
        let x = min(max(crop.x, event.x - width / 2), crop.x + crop.width - width)
        let y = min(max(crop.y, event.y - height / 2), crop.y + crop.height - height)
        return .init(x: x, y: y, width: width, height: height)
    }

    func outputRange(forSourceRange range: AeroMediaTimeRange) -> AeroMediaTimeRange {
        let sourceStart = range.start.value * 1_000_000 / Int64(range.start.timescale)
        let sourceDuration = range.duration.value * 1_000_000 / Int64(range.duration.timescale)
        let start = outputTimeMicroseconds(forSourceTime: sourceStart)
        let end = outputTimeMicroseconds(forSourceTime: sourceStart + sourceDuration)
        guard let outputStart = try? AeroMediaTime(value: start, timescale: 1_000_000),
              let outputDuration = try? AeroMediaTime(value: max(0, end - start), timescale: 1_000_000),
              let outputRange = try? AeroMediaTimeRange(start: outputStart, duration: outputDuration) else { return range }
        return outputRange
    }
}

/// Both renderers compile from this boundary. Preview owns its display backend;
/// export may convert the same commands to an offline Core Animation tree.
nonisolated struct MediaOverlayCommand: Equatable, Sendable {
    let id: UUID
    let kind: AeroOverlay.Kind
    let bounds: AeroNormalizedRect
    let points: [AeroPoint]
    let appearance: AeroOverlay.Appearance
    let transform: AeroOverlay.Transform
    let timeRange: AeroMediaTimeRange?
    let content: String?
}

nonisolated enum MediaOverlayCompiler {
    static func compile(_ snapshot: MediaExportSnapshot) -> [MediaOverlayCommand] {
        let timing = MediaOutputTiming(freezeFrame: snapshot.effects.freezeFrame)
        return snapshot.overlays.map {
            MediaOverlayCommand(
                id: $0.id,
                kind: $0.kind,
                bounds: $0.geometry.bounds,
                points: $0.geometry.points,
                appearance: $0.appearance,
                transform: $0.transform,
                timeRange: $0.timeRange.map(timing.outputRange),
                content: $0.content
            )
        }
    }
}
