import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum MediaProjectBridgeError: Error, Equatable {
    case unsupportedSourceType
    case corruptSource
    case invalidSourceDuration
    case missingPrimarySource
    case wrongSourceMediaType(UUID, AeroMediaMetadata.MediaType)
    case sourceIsNotImmutable(UUID)
    case missingMediaComposition
    case invalidComposition([MediaModelValidationError])
    case invalidPersistedTime
    case invalidExportPreset(UUID)
    case duplicateSliceID(UUID)
    case duplicateTimedOverlayID(UUID)
}

nonisolated struct MediaProjectExportPreset: Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var preset: MediaExportPreset
}

nonisolated struct MediaProjectDocument: Equatable, Sendable {
    var composition: MediaCompositionModel
    var exportPresets: [MediaProjectExportPreset]
}

/// Exact adapter between immutable package originals and the media-core model.
nonisolated enum MediaProjectBridge {
    @discardableResult
    static func importSource(from sourceURL: URL, to packageURL: URL) async throws -> AeroProjectManifest {
        let source = try await inspectSource(at: sourceURL)
        let data: Data
        do { data = try Data(contentsOf: sourceURL, options: .mappedIfSafe) }
        catch { throw MediaProjectBridgeError.corruptSource }

        let store = AeroProjectPackageStore(packageURL: packageURL)
        let asset = try store.storeOriginal(
            data,
            fileExtension: source.fileExtension,
            metadata: source.metadata
        )
        let duration = try rational(from: try requireDuration(source.metadata.duration))
        let mediaAsset = MediaSourceAsset(
            id: asset.id,
            url: try store.URL(forRelativePath: asset.relativePath),
            duration: duration,
            hasVideo: true,
            hasAudio: asset.metadata.hasAudio
        )
        let model = MediaCompositionModel(
            assets: [mediaAsset],
            slices: [MediaSlice(
                sourceAssetID: asset.id,
                sourceRange: RationalTimeRange(start: .zero, duration: duration)
            )]
        )
        var manifest = AeroProjectManifest(assets: [asset], primarySourceAssetID: asset.id)
        manifest.mediaComposition = try persistedState(from: model, exportPresets: [])
        return try store.save(manifest)
    }

    @discardableResult
    static func save(_ document: MediaProjectDocument, to packageURL: URL) throws -> AeroProjectManifest {
        let store = AeroProjectPackageStore(packageURL: packageURL)
        var manifest = try store.load()
        let validation = document.composition.validate()
        guard validation.isEmpty else { throw MediaProjectBridgeError.invalidComposition(validation) }
        try validateUniqueIDs(in: document.composition)
        try validateFiniteCrop(in: document.composition)
        try validateAssets(document.composition.assets, against: manifest, store: store)
        manifest.mediaComposition = try persistedState(
            from: document.composition,
            exportPresets: document.exportPresets
        )
        return try store.save(manifest)
    }

    static func open(from packageURL: URL) throws -> MediaProjectDocument {
        let store = AeroProjectPackageStore(packageURL: packageURL)
        let manifest = try store.load()
        guard let sourceID = manifest.primarySourceAssetID else {
            throw MediaProjectBridgeError.missingPrimarySource
        }
        guard let source = manifest.assets.first(where: { $0.id == sourceID }) else {
            throw AeroProjectPackageError.missingPrimarySource(sourceID)
        }
        guard source.metadata.mediaType == .video || source.metadata.mediaType == .gif else {
            throw MediaProjectBridgeError.wrongSourceMediaType(sourceID, source.metadata.mediaType)
        }
        guard source.isImmutableOriginal else { throw MediaProjectBridgeError.sourceIsNotImmutable(sourceID) }
        guard let state = manifest.mediaComposition else { throw MediaProjectBridgeError.missingMediaComposition }

        let assets = try manifest.assets.compactMap { asset -> MediaSourceAsset? in
            guard asset.metadata.mediaType == .video || asset.metadata.mediaType == .gif else { return nil }
            return MediaSourceAsset(
                id: asset.id,
                url: try store.URL(forRelativePath: asset.relativePath),
                duration: try rational(from: requireDuration(asset.metadata.duration)),
                hasVideo: true,
                hasAudio: asset.metadata.hasAudio
            )
        }
        let model = try model(from: state, assets: assets)
        let validation = model.validate()
        guard validation.isEmpty else { throw MediaProjectBridgeError.invalidComposition(validation) }
        try validateUniqueIDs(in: model)
        try validateFiniteCrop(in: model)
        return MediaProjectDocument(
            composition: model,
            exportPresets: try state.exportPresets.map(exportPreset(from:))
        )
    }

    private static func persistedState(
        from model: MediaCompositionModel,
        exportPresets: [MediaProjectExportPreset]
    ) throws -> AeroMediaCompositionState {
        let presets = try exportPresets.map { value in
            do { try value.preset.validate() }
            catch { throw MediaProjectBridgeError.invalidExportPreset(value.id) }
            guard value.preset.targetBitRate > 0 else { throw MediaProjectBridgeError.invalidExportPreset(value.id) }
            return AeroMediaCompositionState.ExportPreset(
                id: value.id, name: value.name,
                codec: value.preset.codec == .h264 ? .h264 : .hevc,
                pixelSize: value.preset.pixelSize,
                frameRate: value.preset.frameRate,
                targetBitRate: value.preset.targetBitRate
            )
        }
        return AeroMediaCompositionState(
            slices: try model.slices.map { .init(id: $0.id, sourceAssetID: $0.sourceAssetID, sourceRange: try aeroRange(from: $0.sourceRange)) },
            timedOverlays: try model.overlays.map { .init(id: $0.id, kind: persistedKind($0.kind), timeRange: try aeroRange(from: $0.range), payload: $0.payload) },
            canvas: try model.canvas.map { canvas in
                .init(crop: canvas.crop.map { .init(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }, pixelSize: try AeroPixelSize(width: canvas.width, height: canvas.height))
            },
            audio: .init(isMuted: model.audio.isMuted, gain: model.audio.gain),
            exportPresets: presets
        )
    }

    private static func model(from state: AeroMediaCompositionState, assets: [MediaSourceAsset]) throws -> MediaCompositionModel {
        MediaCompositionModel(
            assets: assets,
            slices: try state.slices.map { MediaSlice(id: $0.id, sourceAssetID: $0.sourceAssetID, sourceRange: try rationalRange(from: $0.sourceRange)) },
            overlays: try state.timedOverlays.map { TimedOverlay(id: $0.id, kind: modelKind($0.kind), range: try rationalRange(from: $0.timeRange), payload: $0.payload) },
            canvas: state.canvas.map { .init(crop: $0.crop.map { .init(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }, width: $0.pixelSize.width, height: $0.pixelSize.height) },
            audio: .init(isMuted: state.audio.isMuted, gain: state.audio.gain)
        )
    }

    private static func exportPreset(from value: AeroMediaCompositionState.ExportPreset) throws -> MediaProjectExportPreset {
        let preset = MediaExportPreset(
            codec: value.codec == .h264 ? .h264 : .hevc,
            pixelSize: value.pixelSize,
            frameRate: value.frameRate,
            targetBitRate: value.targetBitRate
        )
        do { try preset.validate() } catch { throw MediaProjectBridgeError.invalidExportPreset(value.id) }
        guard preset.targetBitRate > 0 else { throw MediaProjectBridgeError.invalidExportPreset(value.id) }
        return .init(id: value.id, name: value.name, preset: preset)
    }

    private static func validateAssets(_ assets: [MediaSourceAsset], against manifest: AeroProjectManifest, store: AeroProjectPackageStore) throws {
        let persisted = Dictionary(uniqueKeysWithValues: manifest.assets.map { ($0.id, $0) })
        for asset in assets {
            guard let value = persisted[asset.id] else { throw AeroProjectPackageError.missingAsset(asset.id) }
            guard value.isImmutableOriginal else { throw MediaProjectBridgeError.sourceIsNotImmutable(asset.id) }
            guard value.metadata.mediaType == .video || value.metadata.mediaType == .gif else {
                throw MediaProjectBridgeError.wrongSourceMediaType(asset.id, value.metadata.mediaType)
            }
            guard asset.url.standardizedFileURL == (try store.URL(forRelativePath: value.relativePath)).standardizedFileURL,
                  asset.duration == (try rational(from: requireDuration(value.metadata.duration))) else {
                throw MediaProjectBridgeError.invalidSourceDuration
            }
        }
    }

    private static func validateUniqueIDs(in model: MediaCompositionModel) throws {
        var sliceIDs = Set<UUID>()
        for slice in model.slices where !sliceIDs.insert(slice.id).inserted {
            throw MediaProjectBridgeError.duplicateSliceID(slice.id)
        }
        var overlayIDs = Set<UUID>()
        for overlay in model.overlays where !overlayIDs.insert(overlay.id).inserted {
            throw MediaProjectBridgeError.duplicateTimedOverlayID(overlay.id)
        }
    }

    private static func validateFiniteCrop(in model: MediaCompositionModel) throws {
        guard let crop = model.canvas?.crop else { return }
        guard [crop.x, crop.y, crop.width, crop.height].allSatisfy(\.isFinite) else {
            throw MediaProjectBridgeError.invalidComposition([.invalidCrop])
        }
    }

    private static func aeroTime(from time: RationalTime) throws -> AeroMediaTime {
        do { return try AeroMediaTime(value: time.numerator, timescale: time.denominator) }
        catch { throw MediaProjectBridgeError.invalidPersistedTime }
    }
    private static func rational(from time: AeroMediaTime) throws -> RationalTime {
        do { return try RationalTime(time.value, time.timescale) }
        catch { throw MediaProjectBridgeError.invalidPersistedTime }
    }
    private static func aeroRange(from range: RationalTimeRange) throws -> AeroMediaTimeRange {
        try AeroMediaTimeRange(start: aeroTime(from: range.start), duration: aeroTime(from: range.duration))
    }
    private static func rationalRange(from range: AeroMediaTimeRange) throws -> RationalTimeRange {
        RationalTimeRange(start: try rational(from: range.start), duration: try rational(from: range.duration))
    }
    private static func requireDuration(_ duration: AeroMediaTime?) throws -> AeroMediaTime {
        guard let duration, duration.value > 0 else { throw MediaProjectBridgeError.invalidSourceDuration }
        return duration
    }

    private static func persistedKind(_ kind: TimedOverlayKind) -> AeroMediaCompositionState.TimedOverlay.Kind {
        switch kind { case .callout: .callout; case .text: .text; case .shape: .shape; case .image: .image }
    }
    private static func modelKind(_ kind: AeroMediaCompositionState.TimedOverlay.Kind) -> TimedOverlayKind {
        switch kind { case .callout: .callout; case .text: .text; case .shape: .shape; case .image: .image }
    }

    private struct InspectedSource {
        let fileExtension: String
        let metadata: AeroMediaMetadata
    }

    private static func inspectSource(at url: URL) async throws -> InspectedSource {
        let ext = url.pathExtension.lowercased()
        if ext == "gif" { return try inspectGIF(at: url) }
        guard ext == "mp4" else { throw MediaProjectBridgeError.unsupportedSourceType }
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            guard duration.isNumeric, duration > .zero else { throw MediaProjectBridgeError.invalidSourceDuration }
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = videoTracks.first else { throw MediaProjectBridgeError.corruptSource }
            let size = try await track.load(.naturalSize)
            let frameRate = try await track.load(.nominalFrameRate)
            let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
            return InspectedSource(fileExtension: "mp4", metadata: AeroMediaMetadata(
                mediaType: .video,
                pixelSize: try AeroPixelSize(width: max(1, Int(abs(size.width.rounded()))), height: max(1, Int(abs(size.height.rounded())))),
                duration: try AeroMediaTime(value: duration.value, timescale: duration.timescale),
                nominalFrameRate: frameRate > 0 ? try AeroMediaTime(value: Int64((frameRate * 1_000).rounded()), timescale: 1_000) : nil,
                colorSpaceName: nil,
                hasAudio: hasAudio
            ))
        } catch let error as MediaProjectBridgeError { throw error }
        catch { throw MediaProjectBridgeError.corruptSource }
    }

    private static func inspectGIF(at url: URL) throws -> InspectedSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.gif.identifier,
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw MediaProjectBridgeError.corruptSource }
        var milliseconds: Int64 = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            else { throw MediaProjectBridgeError.corruptSource }
            let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            guard delay.isFinite, delay > 0 else { throw MediaProjectBridgeError.invalidSourceDuration }
            milliseconds += Int64((delay * 1_000).rounded())
        }
        guard milliseconds > 0 else { throw MediaProjectBridgeError.invalidSourceDuration }
        return InspectedSource(fileExtension: "gif", metadata: AeroMediaMetadata(
            mediaType: .gif,
            pixelSize: try AeroPixelSize(width: image.width, height: image.height),
            duration: try AeroMediaTime(value: milliseconds, timescale: 1_000),
            nominalFrameRate: nil,
            colorSpaceName: image.colorSpace?.name as String?,
            hasAudio: false
        ))
    }
}
