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
    }

    init(
        projectID: UUID,
        sourceURL: URL,
        sourceAsset: AeroProjectAsset,
        canvas: AeroProjectCanvas,
        timeline: [AeroTimelineItem] = [],
        overlays: [AeroOverlay] = [],
        eventTracks: [AeroEventTrack] = []
    ) {
        self.projectID = projectID
        self.sourceURL = sourceURL
        self.sourceAsset = sourceAsset
        self.canvas = canvas
        self.timeline = timeline
        self.overlays = overlays.sorted { ($0.zIndex, $0.id.uuidString) < ($1.zIndex, $1.id.uuidString) }
        self.eventTracks = eventTracks
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
        snapshot.overlays.map {
            MediaOverlayCommand(
                id: $0.id,
                kind: $0.kind,
                bounds: $0.geometry.bounds,
                points: $0.geometry.points,
                appearance: $0.appearance,
                transform: $0.transform,
                timeRange: $0.timeRange,
                content: $0.content
            )
        }
    }
}
