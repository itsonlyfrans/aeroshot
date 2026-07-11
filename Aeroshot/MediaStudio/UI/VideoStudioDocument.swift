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

/// Main-actor document boundary for playback, edits, persistence, and export.
/// Source media is immutable; every edit replaces the value-only composition model.
@MainActor
final class VideoStudioDocument: ObservableObject {
    @Published private(set) var model: MediaCompositionModel
    @Published private(set) var manifest: AeroProjectManifest
    @Published private(set) var player = AVPlayer()
    @Published var playhead = RationalTime.zero
    @Published var selection = VideoStudioSelection()
    @Published var selectedOverlayID: UUID?
    @Published var statusMessage = "Ready"
    @Published var exportProgress: Double?
    @Published var lastExportURL: URL?
    @Published var thumbnails: [NSImage] = []
    @Published var waveform: [Float] = []

    let packageURL: URL
    let frameRate: RationalTime
    private let store: AeroProjectPackageStore
    /// Snapshot undo keeps whole model copies; bound the history so
    /// annotation-heavy sessions cannot grow memory without limit.
    static let undoDepthLimit = 100
    private var undoModels: [MediaCompositionModel] = []
    private var redoModels: [MediaCompositionModel] = []
    private var exportTask: Task<Void, Never>?
    private var timeObserver: Any?

    var duration: RationalTime { model.duration }
    var canUndo: Bool { !undoModels.isEmpty }
    var canRedo: Bool { !redoModels.isEmpty }
    var activeOverlays: [TimedOverlay] { model.overlays.filter { $0.range.contains(playhead, includingEnd: true) } }
    var timecode: String { PlaybackMath.timecode(playhead, frameRate: frameRate) }
    var activeCursorEvent: RecordedEffectEvent? {
        let time = Int64(playhead.seconds * 1_000_000)
        return model.effects.events.last { $0.kind == .cursor && $0.timeMicroseconds <= time && time - $0.timeMicroseconds <= 250_000 }
    }
    var activeClickEvents: [RecordedEffectEvent] {
        let time = Int64(playhead.seconds * 1_000_000)
        return model.effects.events.filter { $0.kind == .click && $0.timeMicroseconds <= time && time - $0.timeMicroseconds <= 450_000 }
    }

    init(model: MediaCompositionModel, manifest: AeroProjectManifest, packageURL: URL, frameRate: RationalTime) {
        self.model = model
        self.manifest = manifest
        self.packageURL = packageURL
        self.frameRate = frameRate
        store = AeroProjectPackageStore(packageURL: packageURL)
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
        let document = VideoStudioDocument(model: bridgeDocument.composition, manifest: manifest, packageURL: packageURL, frameRate: frameRate)
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
            guard let range = selection.range else { statusMessage = VideoStudioDocumentError.invalidSelection.localizedDescription; return }
            mutate("Deleted selected range") { try $0.deleteSelectedRange(range) }
            selection = .init()
        case .undo: undo()
        case .redo: redo()
        }
    }

    func seek(to time: RationalTime) {
        let bounded = min(max(time, .zero), duration)
        player.seek(to: bounded.cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
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
        mutate("Updated canvas crop") { value in
            var value = value
            let size = value.canvas.map { ($0.width, $0.height) } ?? (manifest.assets.first?.metadata.pixelSize?.width ?? 1920, manifest.assets.first?.metadata.pixelSize?.height ?? 1080)
            value.canvas = .init(crop: crop, width: size.0, height: size.1)
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

    func save() async {
        do {
            manifest = try MediaProjectBridge.save(.init(composition: model, exportPresets: []), to: packageURL)
            statusMessage = "Saved"
        } catch { statusMessage = "Save failed: \(error.localizedDescription)" }
    }

    func export(to destination: URL) {
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
                let source = try manifestSnapshot.assets.first.unwrap(or: VideoStudioDocumentError.invalidProject)
                let snapshot = MediaExportSnapshot(projectID: manifestSnapshot.id, sourceURL: flattened, sourceAsset: source,
                    canvas: Self.canvasManifest(from: modelSnapshot), overlays: Self.overlayManifest(from: modelSnapshot))
                let size: AeroPixelSize
                if let sourceSize = manifestSnapshot.assets.first?.metadata.pixelSize { size = sourceSize }
                else { size = try AeroPixelSize(width: 1920, height: 1080) }
                let fps = try AeroMediaTime(value: frameRate.numerator, timescale: frameRate.denominator)
                let result = try await MediaExportCoordinator().export(snapshot: snapshot, preset: .h264(size: Self.even(size), frameRate: fps), destination: destination) { value in
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

    func cancelExport() { exportTask?.cancel() }

    private func mutate(_ message: String, transform: (MediaCompositionModel) throws -> MediaCompositionModel) {
        do {
            let candidate = try transform(model)
            guard candidate.validate().isEmpty else { throw VideoStudioDocumentError.invalidProject }
            undoModels.append(model); redoModels.removeAll(); model = candidate
            if undoModels.count > Self.undoDepthLimit { undoModels.removeFirst(undoModels.count - Self.undoDepthLimit) }
            statusMessage = message
            scheduleSaveAndRebuild()
        } catch { statusMessage = error.localizedDescription }
    }

    private func undo() { guard let prior = undoModels.popLast() else { return }; redoModels.append(model); model = prior; scheduleSaveAndRebuild() }
    private func redo() { guard let next = redoModels.popLast() else { return }; undoModels.append(model); model = next; scheduleSaveAndRebuild() }
    private func pause() { player.pause() }
    private func playForward() { player.rate = TransportState(rate: player.rate).applying(.playForward).rate }
    private func step(frames: Int64) { if let delta = try? PlaybackMath.frameStep(frameRate: frameRate) * frames, let next = try? playhead + delta { seek(to: next) } }

    private func scheduleSaveAndRebuild() {
        syncManifest()
        Task {
            manifest = (try? MediaProjectBridge.save(.init(composition: model, exportPresets: []), to: packageURL)) ?? manifest
            try? await rebuildPlayer()
        }
    }

    private func syncManifest() {
        manifest.timeline = model.slices.map { slice in
            AeroTimelineItem(id: slice.id, kind: .sourceRange, sourceAssetID: slice.sourceAssetID,
                              timeRange: try? .init(start: .init(value: slice.sourceRange.start.numerator, timescale: slice.sourceRange.start.denominator),
                                                    duration: .init(value: slice.sourceRange.duration.numerator, timescale: slice.sourceRange.duration.denominator)))
        }
        manifest.overlays = Self.overlayManifest(from: model)
        manifest.canvas = Self.canvasManifest(from: model)
    }

    private func rebuildPlayer() async throws {
        let compiled = try await MediaCompositionCompiler().compile(model)
        let item = AVPlayerItem(asset: compiled.composition)
        item.audioMix = compiled.audioMix
        let retainedTime = min(playhead, model.duration)
        player.replaceCurrentItem(with: item)
        await player.seek(to: retainedTime.cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            guard let value = try? RationalTime(time) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.playhead = min(value, self.duration)
            }
        }
    }

    private func requestThumbnails() {
        let source = model.assets.first?.url
        let duration = model.duration.seconds
        guard let source, duration > 0 else { return }
        Task {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source)); generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 90)
            var images: [NSImage] = []
            for index in 0..<8 {
                let time = CMTime(seconds: duration * Double(index) / 8, preferredTimescale: 600)
                if let image = try? await generator.image(at: time).image { images.append(NSImage(cgImage: image, size: .zero)) }
            }
            thumbnails = images
        }
    }

    private func requestWaveform() {
        guard let source = model.assets.first(where: \.hasAudio)?.url else { return }
        Task {
            waveform = (try? await AudioWaveformGenerator().samples(from: source, sampleCount: 160)) ?? []
        }
    }

    private static func overlayManifest(from model: MediaCompositionModel) -> [AeroOverlay] {
        var result = model.overlays.enumerated().map { index, overlay in
            AeroOverlay(id: overlay.id, kind: (overlay.kind == .text || overlay.kind == .callout) ? .text : .shape,
                        geometry: .init(bounds: .init(x: 0.1, y: 0.1, width: 0.35, height: 0.15), points: []),
                        appearance: .init(strokeRGBA: [1, 0.75, 0.1, 1], fillRGBA: [0.08, 0.08, 0.08, 0.88], strokeWidth: 2, opacity: 1),
                        transform: .init(rotationRadians: 0, scaleX: 1, scaleY: 1), zIndex: index,
                        timeRange: try? .init(start: .init(value: overlay.range.start.numerator, timescale: overlay.range.start.denominator),
                                              duration: .init(value: overlay.range.duration.numerator, timescale: overlay.range.duration.denominator)),
                        content: overlay.payload)
        }
        var index = result.count
        if model.effects.cursorEmphasis > 0 {
            for event in model.effects.events.filter({ $0.kind == .cursor }).prefix(5_000) {
                let size = 0.018 + 0.018 * model.effects.cursorEmphasis
                result.append(effectOverlay(event, size: size, durationMicroseconds: 160_000,
                    color: [1, 0.82, 0.1, 0.85], zIndex: index, marker: "effect.cursor")); index += 1
            }
        }
        if model.effects.clickEmphasis > 0 {
            for event in model.effects.events.filter({ $0.kind == .click }).prefix(2_000) {
                let size = 0.035 + 0.025 * model.effects.clickEmphasis
                result.append(effectOverlay(event, size: size, durationMicroseconds: 450_000,
                    color: [1, 0.42, 0.08, 0.7], zIndex: index, marker: "effect.click")); index += 1
            }
        }
        return result
    }

    private static func effectOverlay(_ event: RecordedEffectEvent, size: Double, durationMicroseconds: Int64,
                                      color: [Double], zIndex: Int, marker: String) -> AeroOverlay {
        let start = try! AeroMediaTime(value: event.timeMicroseconds, timescale: 1_000_000)
        let duration = try! AeroMediaTime(value: durationMicroseconds, timescale: 1_000_000)
        return AeroOverlay(id: UUID(), kind: .shape,
            geometry: .init(bounds: .init(x: max(0, event.x - size / 2), y: max(0, event.y - size / 2),
                                          width: min(size, 1 - max(0, event.x - size / 2)),
                                          height: min(size, 1 - max(0, event.y - size / 2))), points: []),
            appearance: .init(strokeRGBA: color, fillRGBA: nil, strokeWidth: marker == "effect.click" ? 5 : 3, opacity: 1),
            transform: .init(rotationRadians: 0, scaleX: 1, scaleY: 1), zIndex: zIndex,
            timeRange: try! .init(start: start, duration: duration), content: marker)
    }

    private static func canvasManifest(from model: MediaCompositionModel) -> AeroProjectCanvas {
        guard let canvas = model.canvas, let crop = canvas.crop else { return .source }
        return .init(crop: .init(x: crop.x, y: crop.y, width: crop.width, height: crop.height), background: .source,
                     backgroundColorRGBA: nil, aspectRatio: nil, colorSpacePolicy: .preserveSource)
    }

    private static func even(_ size: AeroPixelSize) -> AeroPixelSize {
        try! AeroPixelSize(width: size.width - size.width % 2, height: size.height - size.height % 2)
    }
}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped { guard let self else { throw error() }; return self }
}
