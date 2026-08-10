@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation

nonisolated enum VideoStudioCommand: Equatable, Sendable {
    case togglePlayback, pause, playForward, playReverse, frameBackward, frameForward
    case setIn, setOut, split, deleteSelection, undo, redo
}

nonisolated struct VideoStudioSelection: Equatable, Sendable {
    var inPoint: RationalTime?
    var outPoint: RationalTime?

    var range: RationalTimeRange? {
        guard let inPoint, let outPoint, outPoint > inPoint,
              let duration = try? outPoint - inPoint else { return nil }
        return RationalTimeRange(start: inPoint, duration: duration)
    }
}

nonisolated enum VideoStudioDocumentError: LocalizedError, Equatable {
    case unreadableRecording, missingVideo, invalidProject, invalidSelection

    var errorDescription: String? {
        switch self {
        case .unreadableRecording: "The recording could not be read. Reveal it and verify the file is still available."
        case .missingVideo: "This file does not contain a video track."
        case .invalidProject: "The Media Studio project is incomplete or damaged."
        case .invalidSelection: "Set a valid In and Out range before using this command."
        }
    }
}

nonisolated enum VideoStudioMediaState: Equatable, Sendable {
    case loading
    case available
    case unavailable

    var label: String {
        switch self {
        case .loading: "Loading…"
        case .available: "Available"
        case .unavailable: "Unavailable"
        }
    }
}

nonisolated struct LatestStudioRebuild: Sendable {
    private(set) var current = 0

    mutating func request() -> Int {
        current &+= 1
        return current
    }

    func isCurrent(_ revision: Int) -> Bool { revision == current }

    @discardableResult
    func runIfCurrent(_ revision: Int, _ operation: () -> Void) -> Bool {
        guard isCurrent(revision) else { return false }
        operation()
        return true
    }
}

/// Main-actor document boundary for playback, edits, persistence, and export.
/// Source media is immutable; every edit replaces the value-only composition model.
@MainActor
final class VideoStudioDocument: ObservableObject {
    @Published private(set) var model: MediaCompositionModel
    @Published private(set) var manifest: AeroProjectManifest
    @Published private(set) var player = AVPlayer()
    @Published private(set) var webcamPlayer: AVPlayer?
    @Published var playhead = RationalTime.zero
    @Published var selection = VideoStudioSelection()
    @Published var selectedOverlayID: UUID?
    @Published var statusMessage = "Ready"
    @Published var exportProgress: Double?
    @Published var lastExportURL: URL?
    @Published var thumbnails: [NSImage] = []
    @Published var waveform: [Float] = []
    @Published private(set) var thumbnailState: VideoStudioMediaState = .loading
    @Published private(set) var waveformState: VideoStudioMediaState = .loading

    let packageURL: URL
    let frameRate: RationalTime
    private let orientedSourceSizes: [UUID: CGSize]
    /// Snapshot undo keeps whole model copies; bound the history so
    /// annotation-heavy sessions cannot grow memory without limit.
    static let undoDepthLimit = 100
    private var undoModels: [MediaCompositionModel] = []
    private var redoModels: [MediaCompositionModel] = []
    private var overlayGestureOrigins: [UUID: NormalizedOverlayBounds] = [:]
    private var exportTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var rebuildRevision = LatestStudioRebuild()

    var duration: RationalTime {
        guard let freeze = model.effects.freezeFrame,
              let hold = try? RationalTime(freeze.durationMicroseconds, 1_000_000),
              let result = try? model.duration + hold else { return model.duration }
        return result
    }
    var canUndo: Bool { !undoModels.isEmpty }
    var canRedo: Bool { !redoModels.isEmpty }
    var sourcePlayhead: RationalTime { sourceTime(forOutputTime: playhead) }
    var activeOverlays: [TimedOverlay] { model.overlays.filter { outputRangeContains($0.range) } }
    var timecode: String { PlaybackMath.timecode(playhead, frameRate: frameRate) }
    var activeCursorEvent: RecordedEffectEvent? {
        guard model.effects.cursorEmphasis > 0 else { return nil }
        return model.effects.events.last { $0.kind == .cursor && outputRangeContains($0.timeMicroseconds, durationMicroseconds: MediaOutputTiming.cursorEmphasisDurationMicroseconds) }
    }
    var activeClickEvents: [RecordedEffectEvent] {
        model.effects.events.filter { $0.kind == .click && outputRangeContains($0.timeMicroseconds,
                                                                                durationMicroseconds: MediaOutputTiming.clickEmphasisDurationMicroseconds) }
    }
    var activePunchInEvent: RecordedEffectEvent? {
        let timing = MediaOutputTiming(freezeFrame: model.effects.freezeFrame)
        let outputTime = Int64(playhead.seconds * 1_000_000)
        return timing.activePunchIn(in: model.effects.events.filter {
            $0.kind == .click && model.effects.punchInClickTimes.contains($0.timeMicroseconds)
        }, atOutputTime: outputTime)
    }

    private var webcamSource: MediaSourceAsset? {
        Self.webcamSource(in: model)
    }

    private static func webcamSource(in model: MediaCompositionModel) -> MediaSourceAsset? {
        let primaryID = model.slices.first?.sourceAssetID
        let id = model.effects.webcam.sourceAssetID
            ?? model.assets.first(where: { $0.id != primaryID && $0.hasVideo })?.id
        return id.flatMap { candidate in
            model.assets.first { $0.id == candidate && $0.hasVideo && FileManager.default.fileExists(atPath: $0.url.path) }
        }
    }

    var canRippleDeleteSelection: Bool {
        guard let range = selection.range else { return false }
        return canRippleDelete(range: range)
    }

    init(model: MediaCompositionModel, manifest: AeroProjectManifest, packageURL: URL, frameRate: RationalTime,
         orientedSourceSizes: [UUID: CGSize] = [:]) {
        self.model = model
        self.manifest = manifest
        self.packageURL = packageURL
        self.frameRate = frameRate
        self.orientedSourceSizes = orientedSourceSizes
        self.webcamPlayer = nil
    }

    static func create(from recordingURL: URL, packageURL: URL? = nil) async throws -> VideoStudioDocument {
        guard FileManager.default.fileExists(atPath: recordingURL.path) else { throw VideoStudioDocumentError.unreadableRecording }
        let destination = packageURL ?? recordingURL.deletingPathExtension().appendingPathExtension("aeroshot")
        let manifest = try await MediaProjectBridge.importSource(from: recordingURL, to: destination)
        return try await open(packageURL: destination, manifest: manifest)
    }

    static func open(packageURL: URL, manifest supplied: AeroProjectManifest? = nil) async throws -> VideoStudioDocument {
        let store = AeroProjectPackageStore(packageURL: packageURL)
        let manifest = try supplied ?? store.loadRecoveringIfNeeded()
        guard let id = manifest.primarySourceAssetID,
              let asset = manifest.assets.first(where: { $0.id == id }),
              asset.metadata.mediaType == .video,
              asset.metadata.duration != nil else { throw VideoStudioDocumentError.invalidProject }
        let bridgeDocument = try MediaProjectBridge.open(from: packageURL)
        let fpsValue: AeroMediaTime
        if let nominal = asset.metadata.nominalFrameRate { fpsValue = nominal }
        else { fpsValue = try AeroMediaTime(value: 30, timescale: 1) }
        let frameRate = try RationalTime(fpsValue.value, fpsValue.timescale)
        let orientedSourceSizes = await inspectOrientedSourceSizes(bridgeDocument.composition.assets)
        let document = VideoStudioDocument(model: bridgeDocument.composition, manifest: manifest,
                                           packageURL: packageURL, frameRate: frameRate,
                                           orientedSourceSizes: orientedSourceSizes)
        try await document.rebuildPlayer()
        document.installTimeObserver()
        document.requestThumbnails()
        document.requestWaveform()
        return document
    }

    func perform(_ command: VideoStudioCommand) {
        switch command {
        case .togglePlayback: player.rate == 0 ? playForward() : pause()
        case .pause: pause()
        case .playForward: playForward()
        case .playReverse:
            let state = TransportState(rate: player.rate).applying(.playReverse)
            player.rate = state.rate
        case .frameBackward: step(frames: -1)
        case .frameForward: step(frames: 1)
        case .setIn: selection.inPoint = playhead
        case .setOut: selection.outPoint = playhead
        case .split: mutate("Split") { try $0.split(at: playhead) }
        case .deleteSelection:
            _ = deleteSelection()
        case .undo: undo()
        case .redo: redo()
        }
    }

    @discardableResult
    func deleteSelection() -> Bool {
        guard let range = selection.range else {
            statusMessage = VideoStudioDocumentError.invalidSelection.localizedDescription
            return false
        }
        guard canRippleDelete(range: range) else {
            statusMessage = "Ripple delete only supports a range within the first video slice. Use Trim for a cross-slice range."
            return false
        }
        let changed = mutate("Deleted selected range") { try $0.deleteSelectedRange(range) }
        if changed { selection = .init() }
        return changed
    }

    func canRippleDelete(range: RationalTimeRange) -> Bool {
        guard !range.isEmpty, range.start >= .zero, let first = model.slices.first else { return false }
        return range.end <= first.sourceRange.duration
    }

    func seek(to time: RationalTime) {
        let bounded = min(max(time, .zero), duration)
        player.seek(to: bounded.cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        seekWebcam(toOutputTime: bounded)
        playhead = bounded
    }

    func trimToSelection() {
        guard let range = selection.range else { statusMessage = VideoStudioDocumentError.invalidSelection.localizedDescription; return }
        mutate("Trimmed to selection") { try $0.trim(to: range) }
        selection = .init()
        seek(to: .zero)
    }

    func addCallout(text: String = "Callout") {
        let remaining = (try? duration - playhead) ?? .zero
        let length = min(remaining, (try? RationalTime(3)) ?? remaining)
        guard length > .zero else { return }
        mutate("Added timed callout") { value in
            var value = value
            value.overlays.append(.init(kind: .callout, range: .init(start: playhead, duration: length), payload: text))
            return value
        }
        selectedOverlayID = model.overlays.last?.id
    }

    func updateSelectedOverlay(payload: String, start: Double, duration: Double) {
        guard let id = selectedOverlayID,
              let startTime = try? RationalTime(Int64(max(0, start) * 1_000), 1_000),
              let durationTime = try? RationalTime(Int64(max(0.001, duration) * 1_000), 1_000) else { return }
        mutate("Updated timed callout") { value in
            var value = value
            guard let index = value.overlays.firstIndex(where: { $0.id == id }) else { return value }
            let boundedStart = min(startTime, value.duration)
            let remaining = (try? value.duration - boundedStart) ?? .zero
            value.overlays[index].payload = payload
            value.overlays[index].range = .init(start: boundedStart, duration: min(durationTime, remaining))
            return value
        }
    }

    func updateSelectedOverlayVisual(bounds: NormalizedOverlayBounds? = nil, color: SRGBAColor? = nil) {
        guard bounds != nil || color != nil else { return }
        guard let id = selectedOverlayID else { return }
        mutate("Updated callout appearance") { value in
            var value = value
            guard let index = value.overlays.firstIndex(where: { $0.id == id }) else { return value }
            if let bounds { value.overlays[index].bounds = bounds }
            if let color { value.overlays[index].color = color }
            return value
        }
    }

    /// Begins or continues a live visual gesture without autosaving or rebuilding playback.
    /// The returned value is stable for the gesture and is the basis for translation math.
    @discardableResult
    func beginOverlayVisualGesture(_ id: UUID) -> NormalizedOverlayBounds? {
        if let origin = overlayGestureOrigins[id] { return origin }
        guard let bounds = model.overlays.first(where: { $0.id == id })?.bounds else { return nil }
        overlayGestureOrigins[id] = bounds
        selectedOverlayID = id
        return bounds
    }

    func previewOverlayBounds(_ bounds: NormalizedOverlayBounds, for id: UUID) {
        guard bounds.isValid, let index = model.overlays.firstIndex(where: { $0.id == id }) else { return }
        model.overlays[index].bounds = bounds
    }

    func commitOverlayVisualGesture(_ id: UUID) {
        guard let origin = overlayGestureOrigins.removeValue(forKey: id),
              let index = model.overlays.firstIndex(where: { $0.id == id }) else { return }
        let final = model.overlays[index].bounds
        model.overlays[index].bounds = origin
        guard final != origin else { return }
        mutate("Moved callout") { value in
            var value = value
            guard let candidateIndex = value.overlays.firstIndex(where: { $0.id == id }) else { return value }
            value.overlays[candidateIndex].bounds = final
            return value
        }
    }

    func cancelOverlayVisualGesture(_ id: UUID) {
        guard let origin = overlayGestureOrigins.removeValue(forKey: id),
              let index = model.overlays.firstIndex(where: { $0.id == id }) else { return }
        model.overlays[index].bounds = origin
    }

    func setAudio(muted: Bool? = nil, gain: Float? = nil, fadeIn: Double? = nil, fadeOut: Double? = nil) {
        mutate("Updated audio") { value in
            var value = value
            if let muted { value.audio.isMuted = muted }
            if let gain { value.audio.gain = max(0, min(gain, 2)) }
            if let fadeIn { value.audio.fadeIn = try RationalTime(Int64(max(0, fadeIn) * 1_000), 1_000) }
            if let fadeOut { value.audio.fadeOut = try RationalTime(Int64(max(0, fadeOut) * 1_000), 1_000) }
            return value
        }
    }

    func setCrop(_ crop: NormalizedCrop?) {
        let sourceSize = Self.sourcePixelSize(for: model, in: manifest, orientedSourceSizes: orientedSourceSizes)
            ?? CGSize(width: 1_920, height: 1_080)
        guard let outputSize = Self.outputCanvasSize(for: nil, sourceSize: sourceSize) else { return }
        mutate("Updated canvas crop") { value in
            var value = value
            value.effects.reframeAspectRatio = nil
            value.canvas = .init(crop: crop, width: Int(outputSize.width), height: Int(outputSize.height))
            return value
        }
    }

    func setEffects(events: [RecordedEffectEvent]? = nil, cursorEmphasis: Double? = nil, clickEmphasis: Double? = nil) {
        mutate("Updated recording effects") { value in
            var value = value
            if let events { value.effects.events = events }
            if let cursorEmphasis { value.effects.cursorEmphasis = max(0, min(2, cursorEmphasis)) }
            if let clickEmphasis { value.effects.clickEmphasis = max(0, min(2, clickEmphasis)) }
            return value
        }
    }

    func addFreezeFrame(at time: RationalTime? = nil, duration: Double = 1) {
        let point = min(max(time ?? playhead, .zero), model.duration)
        let hold = Int64(max(0.1, min(duration, 10)) * 1_000_000)
        mutate("Added freeze frame") { value in
            var value = value
            value.effects.freezeFrame = .init(timeMicroseconds: Int64(point.seconds * 1_000_000), durationMicroseconds: hold)
            return value
        }
    }

    func setReframe(aspectRatio: String?) {
        let sourceSize = Self.sourcePixelSize(for: model, in: manifest, orientedSourceSizes: orientedSourceSizes)
            ?? CGSize(width: 1_920, height: 1_080)
        if let aspectRatio {
            guard let canvas = Self.reframeCanvas(sourceSize: sourceSize, aspectRatio: aspectRatio) else { return }
            mutate("Updated reframe") { value in
                var value = value
                value.effects.reframeAspectRatio = aspectRatio
                value.canvas = canvas
                return value
            }
            return
        }

        guard let outputSize = Self.outputCanvasSize(for: nil, sourceSize: sourceSize) else { return }
        mutate("Updated reframe") { value in
            var value = value
            value.effects.reframeAspectRatio = nil
            value.canvas = .init(crop: nil, width: Int(outputSize.width), height: Int(outputSize.height))
            return value
        }
    }

    private static func reframeCanvas(sourceSize: CGSize, aspectRatio: String) -> CanvasState? {
        guard let ratio = Self.aspectRatio(aspectRatio),
              sourceSize.width.isFinite, sourceSize.height.isFinite,
              sourceSize.width >= 2, sourceSize.height >= 2 else { return nil }
        let sourceRatio = sourceSize.width / sourceSize.height
            let crop: NormalizedCrop
            if sourceRatio > ratio {
                let fraction = ratio / sourceRatio
                crop = .init(x: (1 - fraction) / 2, y: 0, width: fraction, height: 1)
            } else {
                let fraction = sourceRatio / ratio
                crop = .init(x: 0, y: (1 - fraction) / 2, width: 1, height: fraction)
            }
        let dimensions: (width: Int, height: Int)
        switch aspectRatio {
        case "16:9": dimensions = (16, 9)
        case "1:1": dimensions = (1, 1)
        case "9:16": dimensions = (9, 16)
        case "4:5": dimensions = (4, 5)
        default: return nil
        }
        let croppedSize = CGSize(width: sourceSize.width * crop.width, height: sourceSize.height * crop.height)
        let limit = min(croppedSize.width / CGFloat(dimensions.width), croppedSize.height / CGFloat(dimensions.height))
        let multiple = Int(limit.rounded(.down)) / 2 * 2
        guard multiple >= 2,
              let outputSize = normalizedOutputSize(CGSize(width: dimensions.width * multiple,
                                                           height: dimensions.height * multiple)) else { return nil }
        return .init(crop: crop, width: Int(outputSize.width), height: Int(outputSize.height))
    }

    var hasWebcamMedia: Bool {
        webcamSource != nil
    }

    func setWebcam(isEnabled: Bool? = nil, corner: String? = nil, isCircular: Bool? = nil) {
        mutate("Updated webcam") { value in
            var value = value
            if value.effects.webcam.sourceAssetID == nil {
                let primaryID = value.slices.first?.sourceAssetID
                value.effects.webcam.sourceAssetID = value.assets.first { $0.id != primaryID && $0.hasVideo }?.id
            }
            if let isEnabled { value.effects.webcam.isEnabled = isEnabled && hasWebcamMedia }
            if let corner { value.effects.webcam.corner = corner }
            if let isCircular { value.effects.webcam.isCircular = isCircular }
            return value
        }
    }

    func setPunchIns(enabled: Bool) {
        mutate("Updated click punch-ins") { value in
            var value = value
            value.effects.punchInClickTimes = enabled ? value.effects.events.filter { $0.kind == .click }.map(\.timeMicroseconds) : []
            return value
        }
    }

    func setClickSound(_ sound: String) {
        guard model.effects.events.contains(where: { $0.kind == .click }) else {
            statusMessage = "Click sound is unavailable without recorded click events."
            return
        }
        mutate("Updated click sound") { value in
            var value = value
            value.effects.clickSound = sound
            return value
        }
    }

    func save() async {
        do {
            manifest = try persistModel()
            statusMessage = "Saved"
        } catch { statusMessage = "Save failed: \(error.localizedDescription)" }
    }

    func export(to destination: URL, codec: MediaExportCodec = .h264) {
        guard exportTask == nil else { return }
        let modelSnapshot = model
        let manifestSnapshot = manifest
        exportProgress = 0
        statusMessage = "Exporting…"
        exportTask = Task { [weak self] in
            guard let self else { return }
            defer { exportTask = nil }
            do {
                let compiled = try await MediaCompositionCompiler().compile(modelSnapshot)
                let flattened = packageURL.appending(path: "generated/export-source-\(UUID().uuidString).mp4")
                defer { try? FileManager.default.removeItem(at: flattened) }
                guard let session = AVAssetExportSession(asset: compiled.composition, presetName: AVAssetExportPresetHighestQuality) else {
                    throw MediaExportError.cannotCreateSession
                }
                session.audioMix = compiled.audioMix
                try await session.export(to: flattened, as: .mp4)
                let flattenedWebcam = try await flattenedWebcamURL(for: modelSnapshot)
                defer {
                    if let flattenedWebcam { try? FileManager.default.removeItem(at: flattenedWebcam) }
                }
                let sourceID = try (modelSnapshot.slices.first?.sourceAssetID ?? manifestSnapshot.primarySourceAssetID)
                    .unwrap(or: VideoStudioDocumentError.invalidProject)
                let source = try manifestSnapshot.assets.first(where: { $0.id == sourceID })
                    .unwrap(or: VideoStudioDocumentError.invalidProject)
                let sourceSize = orientedSourceSizes[sourceID]
                    ?? source.metadata.pixelSize.map { CGSize(width: $0.width, height: $0.height) }
                let outputSize = try Self.outputCanvasSize(for: modelSnapshot.canvas, sourceSize: sourceSize)
                    .unwrap(or: MediaExportError.invalidResolution)
                let renderSize = try AeroPixelSize(width: Int(outputSize.width), height: Int(outputSize.height))
                let snapshot = MediaExportSnapshot(projectID: manifestSnapshot.id, sourceURL: flattened, sourceAsset: source,
                    canvas: Self.canvasManifest(from: modelSnapshot),
                    overlays: Self.overlayManifest(from: modelSnapshot, sourceSize: sourceSize,
                                                   outputSize: CGSize(width: renderSize.width, height: renderSize.height)),
                    effects: modelSnapshot.effects, webcamURL: flattenedWebcam)
                let fps = try AeroMediaTime(value: frameRate.numerator, timescale: frameRate.denominator)
                let preset = codec == .hevc
                    ? MediaExportPreset.hevc(size: renderSize, frameRate: fps)
                    : MediaExportPreset.h264(size: renderSize, frameRate: fps)
                let result = try await MediaExportCoordinator().export(snapshot: snapshot, preset: preset, destination: destination) { value in
                    await MainActor.run { self.exportProgress = value }
                }
                lastExportURL = result.destination
                exportProgress = nil
                statusMessage = "Exported \(ByteCountFormatter.string(fromByteCount: result.byteCount, countStyle: .file))"
            } catch {
                exportProgress = nil
                statusMessage = error is CancellationError || (error as? MediaExportError) == .cancelled ? "Export cancelled" : "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func flattenedWebcamURL(for model: MediaCompositionModel) async throws -> URL? {
        guard model.effects.webcam.isEnabled, let source = Self.webcamSource(in: model) else { return nil }
        let compiled = try await MediaCompositionCompiler().compile(Self.webcamTimelineModel(for: model, source: source))
        let flattened = packageURL.appending(path: "generated/export-webcam-\(UUID().uuidString).mp4")
        do {
            guard let session = AVAssetExportSession(asset: compiled.composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw MediaExportError.cannotCreateSession
            }
            session.audioMix = compiled.audioMix
            try await session.export(to: flattened, as: .mp4)
            return flattened
        } catch {
            Self.removeFailedWebcamFlatten(at: flattened)
            throw error
        }
    }

    nonisolated static func removeFailedWebcamFlatten(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func cancelExport() { exportTask?.cancel() }

    @discardableResult
    private func mutate(_ message: String, transform: (MediaCompositionModel) throws -> MediaCompositionModel) -> Bool {
        do {
            let candidate = try transform(model)
            guard candidate.validate().isEmpty else { throw VideoStudioDocumentError.invalidProject }
            undoModels.append(model); redoModels.removeAll(); model = candidate
            if undoModels.count > Self.undoDepthLimit { undoModels.removeFirst(undoModels.count - Self.undoDepthLimit) }
            statusMessage = message
            scheduleSaveAndRebuild()
            return true
        } catch { statusMessage = error.localizedDescription; return false }
    }

    private func undo() { guard let prior = undoModels.popLast() else { return }; redoModels.append(model); model = prior; scheduleSaveAndRebuild() }
    private func redo() { guard let next = redoModels.popLast() else { return }; undoModels.append(model); model = next; scheduleSaveAndRebuild() }
    private func pause() { player.pause(); webcamPlayer?.pause() }
    private func playForward() {
        let rate = TransportState(rate: player.rate).applying(.playForward).rate
        player.rate = rate
        webcamPlayer?.rate = rate
    }
    private func step(frames: Int64) { if let delta = try? PlaybackMath.frameStep(frameRate: frameRate) * frames, let next = try? playhead + delta { seek(to: next) } }

    private func scheduleSaveAndRebuild() {
        let modelSnapshot = model
        syncManifest()
        let revision = rebuildRevision.request()
        Task { [weak self] in
            guard let self else { return }
            var persisted: AeroProjectManifest?
            guard rebuildRevision.runIfCurrent(revision, {
                persisted = try? persistModel(modelSnapshot)
            }) else { return }
            guard rebuildRevision.isCurrent(revision) else { return }
            if let persisted { manifest = persisted }
            try? await rebuildPlayer(snapshot: modelSnapshot, revision: revision)
        }
    }

    /// Persists editable media state and its derived top-level render manifest from the same pure mappers.
    private func persistModel(_ snapshot: MediaCompositionModel? = nil) throws -> AeroProjectManifest {
        let snapshot = snapshot ?? model
        return try MediaProjectBridge.save(.init(composition: snapshot, exportPresets: []), to: packageURL) { manifest in
            manifest.overlays = Self.overlayManifest(from: snapshot, sourceSize: Self.sourcePixelSize(
                for: snapshot, in: manifest, orientedSourceSizes: self.orientedSourceSizes
            ))
            manifest.canvas = Self.canvasManifest(from: snapshot)
        }
    }

    private func syncManifest() {
        manifest.timeline = model.slices.map { slice in
            AeroTimelineItem(id: slice.id, kind: .sourceRange, sourceAssetID: slice.sourceAssetID,
                              timeRange: try? .init(start: .init(value: slice.sourceRange.start.numerator, timescale: slice.sourceRange.start.denominator),
                                                    duration: .init(value: slice.sourceRange.duration.numerator, timescale: slice.sourceRange.duration.denominator)))
        }
        manifest.overlays = Self.overlayManifest(from: model, sourceSize: Self.sourcePixelSize(
            for: model, in: manifest, orientedSourceSizes: orientedSourceSizes
        ))
        manifest.canvas = Self.canvasManifest(from: model)
    }

    private func rebuildPlayer() async throws {
        try await rebuildPlayer(snapshot: model, revision: rebuildRevision.request())
    }

    private func rebuildPlayer(snapshot: MediaCompositionModel, revision: Int) async throws {
        let compiled = try await MediaCompositionCompiler().compile(snapshot)
        let previewAsset = try await MediaExportCoordinator.applyingFreeze(to: compiled.composition,
                                                                             freezeFrame: snapshot.effects.freezeFrame)
        let item = AVPlayerItem(asset: previewAsset)
        let audioTracks = try await previewAsset.loadTracks(withMediaType: .audio)
        item.audioMix = MediaCompositionCompiler.audioMix(for: audioTracks, audio: snapshot.audio, sourceDuration: snapshot.duration,
                                                           timing: .init(freezeFrame: snapshot.effects.freezeFrame))
        let webcam = await rebuiltWebcamPlayer(for: snapshot)
        guard rebuildRevision.isCurrent(revision) else { return }
        let retainedTime = min(playhead, duration)
        player.replaceCurrentItem(with: item)
        await player.seek(to: retainedTime.cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        webcamPlayer = webcam
        seekWebcam(toOutputTime: retainedTime)
    }

    private func rebuiltWebcamPlayer(for snapshot: MediaCompositionModel) async -> AVPlayer? {
        guard let source = Self.webcamSource(in: snapshot) else { return nil }
        guard let compiled = try? await MediaCompositionCompiler().compile(Self.webcamTimelineModel(for: snapshot, source: source)),
              let preview = try? await MediaExportCoordinator.applyingFreeze(to: compiled.composition,
                                                                              freezeFrame: snapshot.effects.freezeFrame) else { return nil }
        let item = AVPlayerItem(asset: preview)
        let audioTracks = (try? await preview.loadTracks(withMediaType: .audio)) ?? []
        item.audioMix = MediaCompositionCompiler.audioMix(for: audioTracks, audio: .init(isMuted: true),
                                                           sourceDuration: snapshot.duration,
                                                           timing: .init(freezeFrame: snapshot.effects.freezeFrame))
        return AVPlayer(playerItem: item)
    }

    static func webcamTimelineModel(for primary: MediaCompositionModel, source: MediaSourceAsset) -> MediaCompositionModel {
        var model = primary
        model.assets = [source]
        model.slices = primary.slices.map { MediaSlice(sourceAssetID: source.id, sourceRange: $0.sourceRange) }
        model.overlays = []
        model.canvas = nil
        model.audio = .init(isMuted: true)
        model.effects = .init()
        return model
    }

    private func sourceTime(forOutputTime outputTime: RationalTime) -> RationalTime {
        let sourceMicroseconds = MediaOutputTiming(freezeFrame: model.effects.freezeFrame)
            .sourceTimeMicroseconds(forOutputTime: Int64(outputTime.seconds * 1_000_000))
        return (try? RationalTime(sourceMicroseconds, 1_000_000)) ?? outputTime
    }

    private func outputRangeContains(_ range: RationalTimeRange) -> Bool {
        outputRangeContains(Int64(range.start.seconds * 1_000_000),
                            durationMicroseconds: Int64(range.duration.seconds * 1_000_000))
    }

    private func outputRangeContains(_ sourceTime: Int64, durationMicroseconds: Int64) -> Bool {
        let timing = MediaOutputTiming(freezeFrame: model.effects.freezeFrame)
        let outputTime = Int64(playhead.seconds * 1_000_000)
        return timing.isSourceRangeActive(atOutputTime: outputTime, sourceStart: sourceTime,
                                          durationMicroseconds: durationMicroseconds)
    }

    private func seekWebcam(toOutputTime outputTime: RationalTime) {
        webcamPlayer?.seek(to: outputTime.cmTime,
                           toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            guard let value = try? RationalTime(time) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.playhead = min(value, self.duration)
                if self.model.effects.freezeFrame != nil { self.seekWebcam(toOutputTime: self.playhead) }
            }
        }
    }

    private func requestThumbnails() {
        thumbnailState = .loading
        thumbnails = []
        let source = model.assets.first?.url
        let duration = model.duration.seconds
        guard let source, duration > 0 else { thumbnailState = .unavailable; return }
        Task {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source)); generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 90)
            var images: [NSImage] = []
            for index in 0..<8 {
                let time = CMTime(seconds: duration * Double(index) / 8, preferredTimescale: 600)
                if let image = try? await generator.image(at: time).image { images.append(NSImage(cgImage: image, size: .zero)) }
            }
            thumbnails = images
            thumbnailState = images.isEmpty ? .unavailable : .available
        }
    }

    private func requestWaveform() {
        waveformState = .loading
        waveform = []
        guard let source = model.assets.first(where: \.hasAudio)?.url else {
            waveformState = .unavailable
            return
        }
        Task {
            let samples = (try? await AudioWaveformGenerator().samples(from: source, sampleCount: 160)) ?? []
            waveform = samples
            waveformState = samples.isEmpty ? .unavailable : .available
        }
    }

    static func overlayManifest(from model: MediaCompositionModel, sourceSize: CGSize? = nil,
                                outputSize explicitOutputSize: CGSize? = nil) -> [AeroOverlay] {
        var result = model.overlays.enumerated().map { index, overlay in
            AeroOverlay(id: overlay.id, kind: (overlay.kind == .text || overlay.kind == .callout) ? .text : .shape,
                        geometry: .init(bounds: .init(x: overlay.bounds.x, y: overlay.bounds.y,
                                                     width: overlay.bounds.width, height: overlay.bounds.height), points: []),
                        appearance: .init(strokeRGBA: overlay.color.components,
                                          fillRGBA: [0.08, 0.08, 0.08, 0.88], strokeWidth: 2, opacity: 1),
                        transform: .init(rotationRadians: 0, scaleX: 1, scaleY: 1), zIndex: index,
                        timeRange: try? .init(start: .init(value: overlay.range.start.numerator, timescale: overlay.range.start.denominator),
                                              duration: .init(value: overlay.range.duration.numerator, timescale: overlay.range.duration.denominator)),
                        content: overlay.payload)
        }
        var index = result.count
        let fallbackSize = model.canvas.map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: 1, height: 1)
        let effectiveSourceSize = sourceSize ?? fallbackSize
        let requestedOutputSize = explicitOutputSize
            ?? model.canvas.map { CGSize(width: $0.width, height: $0.height) }
            ?? effectiveSourceSize
        let outputSize = normalizedOutputSize(requestedOutputSize) ?? .zero
        let crop = model.canvas?.crop
        let layout = MediaCropLayout.make(
            sourceRect: CGRect(origin: .zero, size: effectiveSourceSize),
            outputRect: CGRect(origin: .zero, size: outputSize),
            normalizedCrop: CGRect(x: crop?.x ?? 0, y: crop?.y ?? 0,
                                   width: crop?.width ?? 1, height: crop?.height ?? 1)
        )
        if model.effects.cursorEmphasis > 0 {
            var visibleCount = 0
            for event in model.effects.events where event.kind == .cursor {
                guard visibleCount < 5_000 else { break }
                guard let point = layout?.normalizedOutputPoint(
                    forSourceNormalized: CGPoint(x: event.x, y: event.y)
                ) else { continue }
                let size = MediaOutputTiming.effectNormalizedSize(kind: .cursor, emphasis: model.effects.cursorEmphasis)
                result.append(effectOverlay(event, point: point, size: size, durationMicroseconds: MediaOutputTiming.cursorEmphasisDurationMicroseconds,
                    appearance: effectAppearance(for: .cursor), zIndex: index, marker: "effect.cursor")); index += 1
                visibleCount += 1
            }
        }
        if model.effects.clickEmphasis > 0 {
            var visibleCount = 0
            for event in model.effects.events where event.kind == .click {
                guard visibleCount < 2_000 else { break }
                guard let point = layout?.normalizedOutputPoint(
                    forSourceNormalized: CGPoint(x: event.x, y: event.y)
                ) else { continue }
                let size = MediaOutputTiming.effectNormalizedSize(kind: .click, emphasis: model.effects.clickEmphasis)
                result.append(effectOverlay(event, point: point, size: size,
                    durationMicroseconds: MediaOutputTiming.clickEmphasisDurationMicroseconds,
                    appearance: effectAppearance(for: .click), zIndex: index, marker: "effect.click")); index += 1
                visibleCount += 1
            }
        }
        return result
    }

    static func effectAppearance(for kind: RecordedEffectKind) -> AeroOverlay.Appearance {
        switch kind {
        case .cursor:
            .init(strokeRGBA: [1, 0.82, 0.1, 0.85], fillRGBA: nil, strokeWidth: 3, opacity: 1)
        case .click:
            .init(strokeRGBA: [1, 0.42, 0.08, 0.7], fillRGBA: nil, strokeWidth: 5, opacity: 1)
        }
    }

    private static func effectOverlay(_ event: RecordedEffectEvent, point: CGPoint, size: Double, durationMicroseconds: Int64,
                                      appearance: AeroOverlay.Appearance, zIndex: Int, marker: String) -> AeroOverlay {
        let start = try! AeroMediaTime(value: event.timeMicroseconds, timescale: 1_000_000)
        let duration = try! AeroMediaTime(value: durationMicroseconds, timescale: 1_000_000)
        return AeroOverlay(id: UUID(), kind: .shape,
            geometry: .init(bounds: .init(x: point.x - size / 2, y: point.y - size / 2,
                                          width: size, height: size), points: []),
            appearance: appearance,
            transform: .init(rotationRadians: 0, scaleX: 1, scaleY: 1), zIndex: zIndex,
            timeRange: try! .init(start: start, duration: duration), content: marker)
    }

    private static func canvasManifest(from model: MediaCompositionModel) -> AeroProjectCanvas {
        guard let canvas = model.canvas, let crop = canvas.crop else { return .source }
        return .init(crop: .init(x: crop.x, y: crop.y, width: crop.width, height: crop.height), background: .source,
                     backgroundColorRGBA: nil, aspectRatio: nil, colorSpacePolicy: .preserveSource)
    }

    private static func aspectRatio(_ value: String) -> Double? {
        switch value {
        case "16:9": 16.0 / 9.0
        case "1:1": 1
        case "9:16": 9.0 / 16.0
        case "4:5": 4.0 / 5.0
        default: nil
        }
    }

    private static func sourcePixelSize(for model: MediaCompositionModel, in manifest: AeroProjectManifest,
                                        orientedSourceSizes: [UUID: CGSize] = [:]) -> CGSize? {
        let sourceID = model.slices.first?.sourceAssetID ?? manifest.primarySourceAssetID
        if let sourceID, let oriented = orientedSourceSizes[sourceID] { return oriented }
        return manifest.assets.first(where: { $0.id == sourceID })?.metadata.pixelSize.map {
            CGSize(width: $0.width, height: $0.height)
        }
    }

    func sourceDisplaySize(for sourceID: UUID?) -> CGSize? {
        guard let sourceID else { return nil }
        return orientedSourceSizes[sourceID]
            ?? manifest.assets.first(where: { $0.id == sourceID })?.metadata.pixelSize.map {
                CGSize(width: $0.width, height: $0.height)
            }
    }

    static func normalizedOutputSize(_ size: CGSize) -> CGSize? {
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 2, size.height >= 2,
              size.width <= CGFloat(Int.max), size.height <= CGFloat(Int.max) else { return nil }
        let width = Int(size.width.rounded(.down))
        let height = Int(size.height.rounded(.down))
        let evenWidth = width - width % 2
        let evenHeight = height - height % 2
        guard evenWidth >= 2, evenHeight >= 2 else { return nil }
        return CGSize(width: evenWidth, height: evenHeight)
    }

    static func outputCanvasSize(for canvas: CanvasState?, sourceSize: CGSize?) -> CGSize? {
        let requested = canvas.map { CGSize(width: $0.width, height: $0.height) }
            ?? sourceSize
            ?? CGSize(width: 1_920, height: 1_080)
        return normalizedOutputSize(requested)
    }

    private static func inspectOrientedSourceSizes(_ assets: [MediaSourceAsset]) async -> [UUID: CGSize] {
        var result: [UUID: CGSize] = [:]
        for source in assets where source.hasVideo {
            let asset = AVURLAsset(url: source.url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let naturalSize = try? await track.load(.naturalSize),
                  let preferredTransform = try? await track.load(.preferredTransform),
                  let rect = MediaSourceGeometry.orientedRect(
                      naturalSize: naturalSize, preferredTransform: preferredTransform
                  ) else { continue }
            result[source.id] = rect.size
        }
        return result
    }

}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped { guard let self else { throw error() }; return self }
}
