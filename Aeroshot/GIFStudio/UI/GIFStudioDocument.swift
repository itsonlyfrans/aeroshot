import AppKit
import Combine
import Foundation
import ImageIO

nonisolated enum GIFStudioCommand: Equatable, Sendable {
    case trim, split, delete, duplicate, undo, redo
}

nonisolated struct GIFStudioSelection: Equatable, Sendable {
    var lowerBound: Int
    var upperBound: Int

    var range: Range<Int> { lowerBound..<upperBound }

    init(lowerBound: Int = 0, upperBound: Int = 1) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    func clamped(to frameCount: Int) -> Self {
        let lower = min(max(0, lowerBound), max(0, frameCount - 1))
        let upper = min(max(lower + 1, upperBound), frameCount)
        return .init(lowerBound: lower, upperBound: upper)
    }
}

nonisolated enum GIFStudioDocumentError: LocalizedError, Equatable {
    case invalidSelection
    case cannotDeleteAllFrames
    case previewUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidSelection: "Select a valid frame range first."
        case .cannotDeleteAllFrames: "A GIF must contain at least one frame."
        case .previewUnavailable: "The selected frame could not be previewed."
        }
    }
}

/// Persistence seam implemented by the project bridge. Tests may use an in-memory adapter.
nonisolated struct GIFStudioProjectAdapter: Sendable {
    let save: @Sendable (GIFDocument) throws -> Void

    init(save: @escaping @Sendable (GIFDocument) throws -> Void) {
        self.save = save
    }
}

/// Main-actor boundary for exact GIF edits, bounded preview, persistence, and export.
/// Preview memory is fixed by `previewCacheCountLimit` and never scales with recording duration.
@MainActor
final class GIFStudioDocument: ObservableObject {
    static let previewCacheCountLimit = 6
    static let previewMaximumPixelSize = 1_280

    @Published private(set) var document: GIFDocument
    @Published var selection: GIFStudioSelection
    @Published var currentFrameIndex = 0
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackRate: GIFPlaybackRate = .one
    @Published private(set) var playbackPositionMicroseconds: Int64 = 0
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var exportProgress: Double?
    @Published private(set) var lastExportURL: URL?
    @Published private(set) var lastExportMetadata: GIFWriteMetadata?

    let packageURL: URL?
    private let projectAdapter: GIFStudioProjectAdapter
    private let writer: GIFWriter
    private let previewDecoder: GIFPreviewDecoder
    private let monotonicNowNanoseconds: @MainActor () -> UInt64
    private let previewCache: GIFPreviewCache
    /// Snapshot undo keeps whole document copies; bound the history so
    /// long editing sessions cannot grow memory without limit.
    static let undoDepthLimit = 100
    private var undoDocuments: [GIFDocument] = []
    private var redoDocuments: [GIFDocument] = []
    private var autosaveTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var playbackGeneration = 0
    private var playbackContentOffsetMicroseconds: Int64 = 0
    private var playbackStartNanoseconds: UInt64 = 0
    private var currentPresentationIndex = 0
    private var wasPlayingBeforeScrub = false
    private var previewRequestedKey: GIFPreviewKey?
    private var previewTasks: [GIFPreviewKey: Task<Void, Never>] = [:]

    var canUndo: Bool { !undoDocuments.isEmpty }
    var canRedo: Bool { !redoDocuments.isEmpty }
    var selectedFrameCount: Int { selection.range.count }
    var selectedDurationMicroseconds: Int64 {
        document.frames[selection.clamped(to: document.frames.count).range]
            .reduce(0) { $0 + $1.durationMicroseconds }
    }
    var residentDecodedPreviewCount: Int { previewCache.count }
    var playbackDurationMicroseconds: Int64 { playbackClock?.plan.durationMicroseconds ?? 1 }
    var playbackProgress: Double {
        min(1, max(0, Double(playbackPositionMicroseconds) / Double(playbackDurationMicroseconds)))
    }
    var activeAnnotations: [GIFTimedAnnotation] {
        guard let range = try? document.timeRange(forFrameAt: currentFrameIndex) else { return [] }
        return document.annotations.filter { $0.range.startMicroseconds < range.endMicroseconds && $0.range.endMicroseconds > range.startMicroseconds }
    }

    init(
        document: GIFDocument,
        projectAdapter: GIFStudioProjectAdapter,
        packageURL: URL? = nil,
        writer: GIFWriter = GIFWriter(),
        previewDecoder: GIFPreviewDecoder = .production,
        monotonicNowNanoseconds: @escaping @MainActor () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.document = document
        self.projectAdapter = projectAdapter
        self.packageURL = packageURL
        self.writer = writer
        self.previewDecoder = previewDecoder
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
        previewCache = GIFPreviewCache(countLimit: Self.previewCacheCountLimit, costLimit: 48 * 1_024 * 1_024)
        selection = .init(lowerBound: 0, upperBound: min(1, document.frames.count))
        loadPreview()
    }

    static func create(from sourceGIF: URL, packageURL: URL) throws -> GIFStudioDocument {
        _ = try GIFProjectBridge.importSource(from: sourceGIF, to: packageURL)
        return try open(packageURL: packageURL)
    }

    static func open(packageURL: URL) throws -> GIFStudioDocument {
        let document = try GIFProjectBridge.open(from: packageURL)
        let adapter = GIFStudioProjectAdapter { value in
            _ = try GIFProjectBridge.save(value, to: packageURL)
        }
        return GIFStudioDocument(document: document, projectAdapter: adapter, packageURL: packageURL)
    }

    deinit {
        autosaveTask?.cancel()
        exportTask?.cancel()
        playbackTask?.cancel()
        previewTasks.values.forEach { $0.cancel() }
    }

    func perform(_ command: GIFStudioCommand) {
        switch command {
        case .trim: trimToSelection()
        case .split: splitAtSelectionStart()
        case .delete: deleteSelection()
        case .duplicate: duplicateSelection()
        case .undo: undo()
        case .redo: redo()
        }
    }

    func applyPreset(_ preset: GIFExportPreset) {
        mutate("Applied \(preset.displayName) preset") { value in
            var value = value
            value.settings = preset.applying(to: value.settings)
            return value
        }
    }

    func setSelection(_ newSelection: GIFStudioSelection) {
        selection = newSelection.clamped(to: document.frames.count)
        seek(toFrame: selection.lowerBound)
    }

    func selectFrame(_ index: Int, extending: Bool = false) {
        let index = min(max(0, index), document.frames.count - 1)
        if extending {
            selection = .init(lowerBound: min(selection.lowerBound, index), upperBound: max(selection.upperBound, index + 1))
        } else {
            selection = .init(lowerBound: index, upperBound: index + 1)
        }
        seek(toFrame: index)
    }

    func moveSelection(by offset: Int, extending: Bool = false) {
        let anchor = offset < 0 ? selection.lowerBound : selection.upperBound - 1
        selectFrame(anchor + offset, extending: extending)
    }

    func togglePlayback() { isPlaying ? pausePlayback() : play() }

    func play() {
        guard playbackTask == nil, let clock = playbackClock else { return }
        if clock.sample(contentElapsedMicroseconds: playbackContentOffsetMicroseconds).isFinished {
            playbackContentOffsetMicroseconds = 0
        }
        playbackStartNanoseconds = monotonicNowNanoseconds()
        isPlaying = true
        playbackGeneration &+= 1
        let generation = playbackGeneration
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.playbackDelay(forGeneration: generation) else { break }
                try? await Task.sleep(for: .microseconds(delay))
            }
            self?.clearPlaybackTask(forGeneration: generation)
        }
    }

    func pausePlayback() {
        guard isPlaying else { return }
        let elapsed = currentPlaybackContentElapsed()
        playbackGeneration &+= 1
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        playbackContentOffsetMicroseconds = elapsed
        applyPlaybackSample(atContentElapsedMicroseconds: elapsed)
    }

    func stopPlayback() {
        playbackGeneration &+= 1
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        playbackContentOffsetMicroseconds = 0
        applyPlaybackSample(atContentElapsedMicroseconds: 0)
    }

    func setPlaybackRate(_ rate: GIFPlaybackRate) {
        guard rate != playbackRate else { return }
        let shouldResume = isPlaying
        if shouldResume { pausePlayback() }
        playbackRate = rate
        playbackStartNanoseconds = monotonicNowNanoseconds()
        applyPlaybackSample(atContentElapsedMicroseconds: playbackContentOffsetMicroseconds)
        if shouldResume { play() }
    }

    func beginScrubbing() {
        wasPlayingBeforeScrub = isPlaying
        pausePlayback()
    }

    func scrub(to progress: Double) {
        let content = Int64((min(1, max(0, progress)) * Double(playbackDurationMicroseconds)).rounded(.down))
        seek(toContentMicroseconds: min(content, max(0, playbackDurationMicroseconds - 1)))
    }

    func endScrubbing() {
        if wasPlayingBeforeScrub { play() }
        wasPlayingBeforeScrub = false
    }

    func cancelPlayback() {
        wasPlayingBeforeScrub = false
        pausePlayback()
    }

    /// Deterministic test seam: applies a simulated wall timestamp without timers.
    func advancePlayback(toWallElapsedMicroseconds elapsed: Int64) {
        playbackContentOffsetMicroseconds = playbackRate.contentMicroseconds(forWallMicroseconds: elapsed)
        applyPlaybackSample(atContentElapsedMicroseconds: playbackContentOffsetMicroseconds)
    }

    /// Deterministic transport seam that services the same monotonic tick as the playback task.
    @discardableResult
    func servicePlaybackTickForTesting() -> Int64? {
        let delay = playbackDelay(forGeneration: playbackGeneration)
        if delay == nil {
            playbackTask?.cancel()
            playbackTask = nil
        }
        return delay
    }

    func setSelectedDuration(milliseconds: Double) {
        let microseconds = Int64((max(1, milliseconds) * 1_000).rounded())
        mutate("Updated range timing") { value in
            var value = value
            try value.setDuration(microseconds, for: selection.range)
            return value
        }
    }

    func setSelectedSpeed(_ multiplier: Double) {
        mutate("Updated range speed") { value in
            var value = value
            try value.applySpeed(multiplier, to: selection.range)
            return value
        }
    }

    func addTimedAnnotation(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let firstRange = try? document.timeRange(forFrameAt: selection.lowerBound) else { return }
        let duration = selectedDurationMicroseconds
        mutate("Added timed annotation") { value in
            var value = value
            value.annotations.append(.init(range: try GIFTimeRange(startMicroseconds: firstRange.startMicroseconds,
                                                                    durationMicroseconds: duration), text: trimmed))
            return value
        }
    }

    func updateSettings(_ transform: (inout GIFExportSettings) -> Void) {
        mutate("Updated export settings") { value in
            var value = value
            transform(&value.settings)
            value.settings = try value.settings.validated()
            return value
        }
    }

    func estimatedOutputBytes(sourceSize: CGSize) -> Int64 {
        document.estimatedOutputBytes(sourceSize: sourceSize)
    }

    /// Readers generally clamp very short GIF delays. Show the effective timing used for guidance.
    func effectiveDelayDescription(for requestedMilliseconds: Double) -> String {
        let requested = max(1, requestedMilliseconds)
        let effective = max(20, requested)
        return effective == requested
            ? String(format: "%.0f ms per frame", effective)
            : String(format: "%.0f ms requested · about %.0f ms effective in many players", requested, effective)
    }

    func saveNow() {
        autosaveTask?.cancel()
        do {
            try projectAdapter.save(document)
            statusMessage = "Saved"
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func export(to destination: URL) {
        guard exportTask == nil else { return }
        let snapshot = document
        exportProgress = 0
        statusMessage = "Exporting…"
        exportTask = Task { [weak self] in
            guard let self else { return }
            defer { exportTask = nil }
            do {
                exportProgress = 0.1
                let metadata = try await writer.write(snapshot, to: destination)
                try Task.checkCancellation()
                exportProgress = 1
                lastExportURL = destination
                lastExportMetadata = metadata
                statusMessage = "Exported \(ByteCountFormatter.string(fromByteCount: metadata.byteCount, countStyle: .file))"
                exportProgress = nil
            } catch {
                exportProgress = nil
                statusMessage = error is CancellationError || (error as? GIFCoreError) == .cancelled
                    ? "Export cancelled"
                    : "Export failed: \(error.localizedDescription)"
            }
        }
    }

    func cancelExport() { exportTask?.cancel() }

    func loadPreview() {
        guard document.frames.indices.contains(currentFrameIndex) else { previewImage = nil; return }
        let key = previewKey(forFrameAt: currentFrameIndex)
        previewRequestedKey = key
        if let cached = previewCache.image(for: key) {
            previewImage = cached
            readAhead()
            return
        }
        previewImage = nil
        requestDecode(for: key)
        readAhead()
    }

    private var playbackClock: GIFPlaybackClock? {
        try? GIFPlaybackClock(
            durations: document.frames.map(\.durationMicroseconds),
            rate: playbackRate,
            pingPong: document.settings.pingPong,
            loop: document.settings.loop
        )
    }

    private func previewKey(forFrameAt index: Int) -> GIFPreviewKey {
        .init(
            sourceURL: document.frames[index].sourceURL,
            crop: document.settings.crop,
            maximumPixelSize: Self.previewMaximumPixelSize
        )
    }

    private func requestDecode(for key: GIFPreviewKey) {
        guard previewCache.image(for: key) == nil, previewTasks[key] == nil,
              previewTasks.count < 3 else { return }
        while previewCache.count + previewTasks.count >= Self.previewCacheCountLimit {
            guard previewCache.evictLeastRecentlyUsed() else { return }
        }
        previewTasks[key] = Task { [weak self] in
            guard let decoder = self?.previewDecoder else { return }
            let decoded = await decoder.decode(key)
            guard let self else { return }
            previewTasks[key] = nil
            guard !Task.isCancelled else { return }
            guard let decoded else {
                if previewRequestedKey == key {
                    statusMessage = GIFStudioDocumentError.previewUnavailable.localizedDescription
                }
                if let requested = previewRequestedKey, requested != key,
                   previewCache.image(for: requested) == nil {
                    requestDecode(for: requested)
                }
                readAhead()
                return
            }
            let image = NSImage(cgImage: decoded.image, size: .zero)
            previewCache.insert(image, for: key, cost: decoded.cost)
            if previewRequestedKey == key { previewImage = image }
            if let requested = previewRequestedKey, previewCache.image(for: requested) == nil {
                requestDecode(for: requested)
            }
            readAhead()
        }
    }

    private func readAhead() {
        guard let clock = playbackClock, !clock.plan.entries.isEmpty else { return }
        var seen: Set<GIFPreviewKey> = [previewKey(forFrameAt: currentFrameIndex)]
        guard clock.plan.entries.count > 1 else { return }
        var distinctForwardCount = 0
        for offset in 1..<clock.plan.entries.count {
            let index = (currentPresentationIndex + offset) % clock.plan.entries.count
            let key = previewKey(forFrameAt: clock.plan.entries[index].sourceIndex)
            if seen.insert(key).inserted {
                distinctForwardCount += 1
                if previewCache.image(for: key) == nil { requestDecode(for: key) }
                if distinctForwardCount == 2 { break }
            }
        }
    }

    private func seek(toFrame frameIndex: Int) {
        guard let clock = playbackClock,
              let presentationIndex = clock.plan.entries.firstIndex(where: { $0.sourceIndex == frameIndex }) else { return }
        let content = presentationIndex == 0 ? 0 : clock.plan.entries[presentationIndex - 1].endMicroseconds
        seek(toContentMicroseconds: content)
    }

    private func seek(toContentMicroseconds content: Int64) {
        let shouldResume = isPlaying
        if shouldResume { pausePlayback() }
        let content = min(max(0, content), max(0, playbackDurationMicroseconds - 1))
        playbackContentOffsetMicroseconds = content
        playbackStartNanoseconds = monotonicNowNanoseconds()
        applyPlaybackSample(atContentElapsedMicroseconds: playbackContentOffsetMicroseconds)
        if shouldResume { play() }
    }

    private func currentPlaybackContentElapsed() -> Int64 {
        guard isPlaying else { return playbackContentOffsetMicroseconds }
        let now = monotonicNowNanoseconds()
        let delta = now >= playbackStartNanoseconds ? (now - playbackStartNanoseconds) / 1_000 : 0
        let deltaMicroseconds = playbackRate.contentMicroseconds(forWallMicroseconds: Int64(clamping: delta))
        let (value, overflow) = playbackContentOffsetMicroseconds.addingReportingOverflow(deltaMicroseconds)
        return overflow ? Int64.max : value
    }

    private func playbackDelay(forGeneration generation: Int) -> Int64? {
        guard isPlaying, playbackGeneration == generation else { return nil }
        let elapsed = currentPlaybackContentElapsed()
        guard let sample = applyPlaybackSample(atContentElapsedMicroseconds: elapsed) else { return nil }
        if sample.isFinished {
            playbackContentOffsetMicroseconds = elapsed
            isPlaying = false
            return nil
        }
        guard let remaining = sample.contentMicrosecondsUntilNextBoundary else { return nil }
        return max(1, playbackRate.wallMicroseconds(forContentMicroseconds: remaining))
    }

    private func clearPlaybackTask(forGeneration generation: Int) {
        if playbackGeneration == generation { playbackTask = nil }
    }

    @discardableResult
    private func applyPlaybackSample(atContentElapsedMicroseconds elapsed: Int64) -> GIFPlaybackClock.Sample? {
        guard let clock = playbackClock else { return nil }
        let sample = clock.sample(contentElapsedMicroseconds: elapsed)
        currentPresentationIndex = sample.presentationIndex
        playbackPositionMicroseconds = sample.cycleElapsedMicroseconds
        let changed = currentFrameIndex != sample.frameIndex
        currentFrameIndex = sample.frameIndex
        if changed || previewImage == nil { loadPreview() } else { readAhead() }
        return sample
    }

    private func resetPlaybackAfterDocumentMutation() {
        playbackGeneration &+= 1
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        wasPlayingBeforeScrub = false
        let clampedFrame = min(max(0, currentFrameIndex), document.frames.count - 1)
        currentFrameIndex = clampedFrame
        playbackContentOffsetMicroseconds = 0
        playbackPositionMicroseconds = 0
        currentPresentationIndex = 0
        previewImage = nil
        seek(toFrame: clampedFrame)
    }

    private func trimToSelection() {
        mutate("Trimmed to selection") { try $0.trimmed(to: selection.range) }
        selection = .init(lowerBound: 0, upperBound: document.frames.count)
        currentFrameIndex = 0
        resetPlaybackAfterDocumentMutation()
    }

    private func splitAtSelectionStart() {
        let index = selection.lowerBound
        guard index > 0, index < document.frames.count else {
            statusMessage = GIFStudioDocumentError.invalidSelection.localizedDescription
            return
        }
        mutate("Split and kept trailing range") { try $0.split(at: index).1 }
        selection = .init(lowerBound: 0, upperBound: min(1, document.frames.count))
        currentFrameIndex = 0
        resetPlaybackAfterDocumentMutation()
    }

    private func deleteSelection() {
        guard selection.range.count < document.frames.count else {
            statusMessage = GIFStudioDocumentError.cannotDeleteAllFrames.localizedDescription
            return
        }
        mutate("Deleted selected range") { value in
            var value = value
            try value.delete(selection.range)
            return value
        }
        selection = selection.clamped(to: document.frames.count)
        currentFrameIndex = selection.lowerBound
        resetPlaybackAfterDocumentMutation()
    }

    private func duplicateSelection() {
        mutate("Duplicated selected range") { value in
            var value = value
            let copies = try value.frames[selection.range].map {
                try GIFFrame(sourceURL: $0.sourceURL, durationMicroseconds: $0.durationMicroseconds)
            }
            value.frames.insert(contentsOf: copies, at: selection.upperBound)
            return value
        }
        selection = .init(lowerBound: selection.upperBound, upperBound: selection.upperBound + selectedFrameCount)
            .clamped(to: document.frames.count)
    }

    private func mutate(_ message: String, transform: (GIFDocument) throws -> GIFDocument) {
        do {
            let candidate = try transform(document)
            undoDocuments.append(document)
            if undoDocuments.count > Self.undoDepthLimit {
                undoDocuments.removeFirst(undoDocuments.count - Self.undoDepthLimit)
            }
            redoDocuments.removeAll()
            document = candidate
            selection = selection.clamped(to: candidate.frames.count)
            statusMessage = message
            scheduleAutosave()
            resetPlaybackAfterDocumentMutation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func undo() {
        guard let prior = undoDocuments.popLast() else { return }
        redoDocuments.append(document)
        document = prior
        selection = selection.clamped(to: document.frames.count)
        statusMessage = "Undid edit"
        scheduleAutosave()
        resetPlaybackAfterDocumentMutation()
    }

    private func redo() {
        guard let next = redoDocuments.popLast() else { return }
        undoDocuments.append(document)
        document = next
        selection = selection.clamped(to: document.frames.count)
        statusMessage = "Redid edit"
        scheduleAutosave()
        resetPlaybackAfterDocumentMutation()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let snapshot = document
        let adapter = projectAdapter
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
                try adapter.save(snapshot)
                guard !Task.isCancelled else { return }
                self?.statusMessage = "Saved"
            } catch is CancellationError {
                return
            } catch {
                self?.statusMessage = "Autosave failed: \(error.localizedDescription)"
            }
        }
    }
}
