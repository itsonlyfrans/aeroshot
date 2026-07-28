import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum GIFProjectBridgeError: Error, Equatable {
    case unsupportedSourceType
    case corruptSource
    case missingPrimarySource
    case wrongSourceMediaType(UUID, AeroMediaMetadata.MediaType)
    case sourceIsNotImmutable(UUID)
    case invalidGIFState(AeroGIFEditStateError)
    case invalidGIFDocument
    case generatedCacheLimitExceeded
    case decodedResourceLimitExceeded
    case missingFrameDerivative(UUID)
}

extension GIFProjectBridgeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedSourceType:
            "Choose a GIF file to import."
        case .corruptSource:
            "This GIF is damaged or unreadable."
        case .missingPrimarySource:
            "This project is missing its original GIF."
        case .wrongSourceMediaType:
            "This project’s primary source is not a GIF."
        case .sourceIsNotImmutable:
            "The project’s original GIF is not marked as immutable."
        case .invalidGIFState, .invalidGIFDocument:
            "This GIF project contains invalid edit data."
        case .generatedCacheLimitExceeded:
            "This GIF exceeds the configured frame or cache limit."
        case .decodedResourceLimitExceeded:
            "This GIF is too large to open safely."
        case .missingFrameDerivative:
            "Aeroshot couldn’t rebuild one of this GIF’s frames."
        }
    }
}

/// Adapter between a complete editable GIF document and an immutable-source
/// `.aeroshot` package. PNG frame files live only in the purgeable generated
/// area and are deterministically rebuilt from the source GIF when absent.
nonisolated enum GIFProjectBridge {
    static let maximumDecodedDimension = 16_384
    static let maximumDecodedPixelCount: Int64 = 64 * 1_024 * 1_024

    @discardableResult
    static func importSource(
        from sourceURL: URL,
        to packageURL: URL,
        limits: GIFFrameSpool.Limits = .recordingDefault
    ) throws -> AeroProjectManifest {
        guard limits.maximumFrameCount > 0, limits.maximumBytes > 0 else {
            throw GIFProjectBridgeError.generatedCacheLimitExceeded
        }
        let decoded = try inspect(sourceURL, limits: limits)
        let data: Data
        do { data = try Data(contentsOf: sourceURL, options: .mappedIfSafe) }
        catch { throw GIFProjectBridgeError.corruptSource }

        let store = AeroProjectPackageStore(packageURL: packageURL)
        let asset = try store.storeOriginal(
            data,
            fileExtension: "gif",
            metadata: AeroMediaMetadata(
                mediaType: .gif,
                pixelSize: try AeroPixelSize(width: decoded.width, height: decoded.height),
                duration: try AeroMediaTime(value: decoded.totalMicroseconds, timescale: 1_000_000),
                nominalFrameRate: nil,
                colorSpaceName: decoded.colorSpaceName,
                hasAudio: false
            )
        )
        let state = try writeDerivatives(
            decoded.frames,
            to: store,
            limits: limits,
            settings: GIFExportSettings()
        )
        var manifest = AeroProjectManifest(assets: [asset], primarySourceAssetID: asset.id)
        manifest.gifEditState = state
        return try store.save(manifest)
    }

    @discardableResult
    static func save(_ document: GIFDocument, to packageURL: URL) throws -> AeroProjectManifest {
        let store = AeroProjectPackageStore(packageURL: packageURL)
        var manifest = try store.load()
        let source = try requireSource(in: manifest)
        _ = source
        do { _ = try document.settings.validated() }
        catch { throw GIFProjectBridgeError.invalidGIFDocument }

        let limits = manifest.gifEditState.map {
            GIFFrameSpool.Limits(maximumFrameCount: $0.spoolMaximumFrameCount, maximumBytes: $0.spoolMaximumBytes)
        } ?? .recordingDefault
        guard document.frames.count <= limits.maximumFrameCount else {
            throw GIFProjectBridgeError.generatedCacheLimitExceeded
        }
        let generated = try generatedDirectory(in: store)
        let priorSourceIndexByURL: [URL: Int] = Dictionary(uniqueKeysWithValues: try (manifest.gifEditState?.frames ?? []).compactMap {
            guard let index = $0.sourceFrameIndex else { return nil }
            return (try store.URL(forRelativePath: $0.generatedRelativePath).standardizedFileURL, index)
        })
        var byteCount: Int64 = 0
        var persistedFrames: [AeroGIFEditState.Frame] = []
        for frame in document.frames {
            guard frame.durationMicroseconds > 0 else { throw GIFProjectBridgeError.invalidGIFDocument }
            let relativePath = framePath(for: frame.id)
            let destination = try store.URL(forRelativePath: relativePath)
            let sourceURL = frame.sourceURL.standardizedFileURL
            let sourceFrameIndex = priorSourceIndexByURL[sourceURL]
            if sourceURL != destination.standardizedFileURL {
                guard let data = try? Data(contentsOf: sourceURL, options: .mappedIfSafe) else {
                    throw GIFProjectBridgeError.missingFrameDerivative(frame.id)
                }
                try data.write(to: destination, options: .atomic)
            }
            let size = Int64((try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            guard byteCount <= limits.maximumBytes - size else {
                throw GIFProjectBridgeError.generatedCacheLimitExceeded
            }
            byteCount += size
            persistedFrames.append(.init(
                id: frame.id,
                generatedRelativePath: relativePath,
                durationMicroseconds: frame.durationMicroseconds,
                sourceFrameIndex: sourceFrameIndex
            ))
        }
        _ = generated
        do {
            manifest.gifEditState = try persistedState(
                frames: persistedFrames,
                settings: document.settings,
                annotations: document.annotations,
                limits: limits
            )
        } catch let error as AeroGIFEditStateError {
            throw GIFProjectBridgeError.invalidGIFState(error)
        }
        return try store.save(manifest)
    }

    static func open(from packageURL: URL) throws -> GIFDocument {
        let store = AeroProjectPackageStore(packageURL: packageURL)
        let manifest = try store.load()
        let source = try requireSource(in: manifest)
        let sourceURL = try store.URL(forRelativePath: source.relativePath)

        let state: AeroGIFEditState
        if let persisted = manifest.gifEditState {
            do { try persisted.validate() }
            catch let error as AeroGIFEditStateError { throw GIFProjectBridgeError.invalidGIFState(error) }
            state = persisted
            if try derivativesNeedRebuild(state, store: store) {
                let limits = GIFFrameSpool.Limits(
                    maximumFrameCount: state.spoolMaximumFrameCount,
                    maximumBytes: state.spoolMaximumBytes
                )
                let decoded = try inspect(sourceURL, limits: limits)
                let images = try state.frames.map { frame -> CGImage in
                    guard let index = frame.sourceFrameIndex, decoded.frames.indices.contains(index) else {
                        throw GIFProjectBridgeError.missingFrameDerivative(frame.id)
                    }
                    return decoded.frames[index].image
                }
                try rewriteDerivatives(images, state: state, store: store, limits: limits)
            }
        } else {
            // Legacy GIF projects acquire default editor settings in memory;
            // opening does not mutate their manifest.
            let decoded = try inspect(sourceURL, limits: .recordingDefault)
            state = try writeDerivatives(decoded.frames, to: store, limits: .recordingDefault, settings: .init())
        }

        do {
            return try GIFDocument(
                frames: state.frames.map {
                    try GIFFrame(
                        id: $0.id,
                        sourceURL: store.URL(forRelativePath: $0.generatedRelativePath),
                        durationMicroseconds: $0.durationMicroseconds
                    )
                },
                settings: settings(from: state),
                annotations: try state.annotations.map {
                    GIFTimedAnnotation(id: $0.id,
                        range: try GIFTimeRange(startMicroseconds: $0.startMicroseconds, durationMicroseconds: $0.durationMicroseconds),
                        text: $0.text)
                }
            )
        } catch { throw GIFProjectBridgeError.invalidGIFDocument }
    }

    private struct DecodedFrame {
        var id: UUID
        var image: CGImage
        var durationMicroseconds: Int64
    }

    private struct DecodedGIF {
        var frames: [DecodedFrame]
        var width: Int
        var height: Int
        var totalMicroseconds: Int64
        var colorSpaceName: String?
    }

    private static func inspect(_ url: URL, limits: GIFFrameSpool.Limits) throws -> DecodedGIF {
        guard url.pathExtension.lowercased() == "gif" else { throw GIFProjectBridgeError.unsupportedSourceType }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.gif.identifier,
              CGImageSourceGetCount(source) > 0
        else { throw GIFProjectBridgeError.corruptSource }
        guard CGImageSourceGetCount(source) <= limits.maximumFrameCount else {
            throw GIFProjectBridgeError.generatedCacheLimitExceeded
        }

        var frames: [DecodedFrame] = []
        var total: Int64 = 0
        var decodedPixels: Int64 = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            else { throw GIFProjectBridgeError.corruptSource }
            decodedPixels = try addingDecodedFramePixels(
                width: width,
                height: height,
                to: decodedPixels
            )
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil),
                  image.width == width, image.height == height
            else { throw GIFProjectBridgeError.corruptSource }
            let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let seconds = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            guard seconds.isFinite, seconds > 0 else { throw GIFProjectBridgeError.corruptSource }
            let microsDouble = seconds * 1_000_000
            guard microsDouble.isFinite, microsDouble >= 1, microsDouble <= Double(Int64.max) else {
                throw GIFProjectBridgeError.corruptSource
            }
            let micros = Int64(microsDouble.rounded())
            guard total <= Int64.max - micros else { throw GIFProjectBridgeError.corruptSource }
            total += micros
            frames.append(.init(id: UUID(), image: image, durationMicroseconds: micros))
        }
        guard let first = frames.first else { throw GIFProjectBridgeError.corruptSource }
        return DecodedGIF(
            frames: frames, width: first.image.width, height: first.image.height,
            totalMicroseconds: total, colorSpaceName: first.image.colorSpace?.name as String?
        )
    }

    static func addingDecodedFramePixels(width: Int, height: Int, to current: Int64) throws -> Int64 {
        guard width > 0, height > 0,
              width <= maximumDecodedDimension, height <= maximumDecodedDimension,
              current >= 0, current <= maximumDecodedPixelCount,
              Int64(width) <= (maximumDecodedPixelCount - current) / Int64(height)
        else { throw GIFProjectBridgeError.decodedResourceLimitExceeded }
        return current + Int64(width) * Int64(height)
    }

    private static func writeDerivatives(
        _ frames: [DecodedFrame], to store: AeroProjectPackageStore,
        limits: GIFFrameSpool.Limits, settings: GIFExportSettings
    ) throws -> AeroGIFEditState {
        let stateFrames = frames.enumerated().map { index, frame in
            AeroGIFEditState.Frame(
                id: frame.id, generatedRelativePath: framePath(for: frame.id),
                durationMicroseconds: frame.durationMicroseconds,
                sourceFrameIndex: index
            )
        }
        let state = try persistedState(frames: stateFrames, settings: settings, limits: limits)
        try rewriteDerivatives(frames.map(\.image), state: state, store: store, limits: limits)
        return state
    }

    private static func rewriteDerivatives(
        _ images: [CGImage], state: AeroGIFEditState,
        store: AeroProjectPackageStore, limits: GIFFrameSpool.Limits
    ) throws {
        guard images.count == state.frames.count else { throw GIFProjectBridgeError.corruptSource }
        _ = try generatedDirectory(in: store)
        var total: Int64 = 0
        for (image, frame) in zip(images, state.frames) {
            let url = try store.URL(forRelativePath: frame.generatedRelativePath)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { throw GIFProjectBridgeError.corruptSource }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw GIFProjectBridgeError.corruptSource }
            let size = Int64((try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            guard total <= limits.maximumBytes - size else {
                try? FileManager.default.removeItem(at: url)
                throw GIFProjectBridgeError.generatedCacheLimitExceeded
            }
            total += size
        }
    }

    private static func derivativesNeedRebuild(_ state: AeroGIFEditState, store: AeroProjectPackageStore) throws -> Bool {
        for frame in state.frames {
            let url = try store.URL(forRelativePath: frame.generatedRelativePath)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return true }
        }
        return false
    }

    private static func persistedState(
        frames: [AeroGIFEditState.Frame], settings: GIFExportSettings,
        annotations: [GIFTimedAnnotation] = [], limits: GIFFrameSpool.Limits
    ) throws -> AeroGIFEditState {
        try AeroGIFEditState(
            frames: frames,
            loop: persistedLoop(settings.loop),
            pingPong: settings.pingPong,
            outputWidth: settings.outputWidth,
            outputHeight: settings.outputHeight,
            paletteSize: settings.paletteSize,
            dither: settings.dither == .none ? .none : .ordered,
            preservesTransparency: settings.preservesTransparency,
            quality: settings.quality,
            spoolMaximumFrameCount: limits.maximumFrameCount,
            spoolMaximumBytes: limits.maximumBytes,
            crop: settings.crop.map { .init(x: $0.x, y: $0.y, width: $0.width, height: $0.height) },
            annotations: annotations.map { .init(id: $0.id, startMicroseconds: $0.range.startMicroseconds,
                                                 durationMicroseconds: $0.range.durationMicroseconds, text: $0.text) }
        )
    }

    private static func settings(from state: AeroGIFEditState) -> GIFExportSettings {
        GIFExportSettings(
            loop: modelLoop(state.loop), pingPong: state.pingPong,
            outputWidth: state.outputWidth, outputHeight: state.outputHeight,
            paletteSize: state.paletteSize,
            dither: state.dither == .none ? .none : .ordered,
            preservesTransparency: state.preservesTransparency,
            quality: state.quality,
            crop: state.crop.map { .init(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        )
    }

    private static func persistedLoop(_ loop: GIFLoop) -> AeroGIFEditState.Loop {
        switch loop { case .once: .once; case .count(let count): .count(count); case .forever: .forever }
    }

    private static func modelLoop(_ loop: AeroGIFEditState.Loop) -> GIFLoop {
        switch loop { case .once: .once; case .count(let count): .count(count); case .forever: .forever }
    }

    private static func requireSource(in manifest: AeroProjectManifest) throws -> AeroProjectAsset {
        guard let id = manifest.primarySourceAssetID else { throw GIFProjectBridgeError.missingPrimarySource }
        guard let source = manifest.assets.first(where: { $0.id == id }) else {
            throw AeroProjectPackageError.missingPrimarySource(id)
        }
        guard source.metadata.mediaType == .gif else {
            throw GIFProjectBridgeError.wrongSourceMediaType(id, source.metadata.mediaType)
        }
        guard source.isImmutableOriginal else { throw GIFProjectBridgeError.sourceIsNotImmutable(id) }
        return source
    }

    private static func generatedDirectory(in store: AeroProjectPackageStore) throws -> URL {
        try store.preparePackage()
        let url = try store.URL(forRelativePath: "generated/gif-frames")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func framePath(for id: UUID) -> String {
        "generated/gif-frames/\(id.uuidString.lowercased()).png"
    }
}
