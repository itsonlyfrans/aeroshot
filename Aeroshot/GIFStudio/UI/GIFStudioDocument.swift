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
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var exportProgress: Double?
    @Published private(set) var lastExportURL: URL?
    @Published private(set) var lastExportMetadata: GIFWriteMetadata?

    let packageURL: URL?
    private let projectAdapter: GIFStudioProjectAdapter
    private let writer: GIFWriter
    private let previewCache = NSCache<NSString, NSImage>()
    /// Snapshot undo keeps whole document copies; bound the history so
    /// long editing sessions cannot grow memory without limit.
    static let undoDepthLimit = 100
    private var undoDocuments: [GIFDocument] = []
    private var redoDocuments: [GIFDocument] = []
    private var autosaveTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?

    var canUndo: Bool { !undoDocuments.isEmpty }
    var canRedo: Bool { !redoDocuments.isEmpty }
    var selectedFrameCount: Int { selection.range.count }
    var selectedDurationMicroseconds: Int64 {
        document.frames[selection.clamped(to: document.frames.count).range]
            .reduce(0) { $0 + $1.durationMicroseconds }
    }
    var residentDecodedPreviewCount: Int { previewCache.countLimit }
    var activeAnnotations: [GIFTimedAnnotation] {
        guard let range = try? document.timeRange(forFrameAt: currentFrameIndex) else { return [] }
        return document.annotations.filter { $0.range.startMicroseconds < range.endMicroseconds && $0.range.endMicroseconds > range.startMicroseconds }
    }

    init(
        document: GIFDocument,
        projectAdapter: GIFStudioProjectAdapter,
        packageURL: URL? = nil,
        writer: GIFWriter = GIFWriter()
    ) {
        self.document = document
        self.projectAdapter = projectAdapter
        self.packageURL = packageURL
        self.writer = writer
        selection = .init(lowerBound: 0, upperBound: min(1, document.frames.count))
        previewCache.countLimit = Self.previewCacheCountLimit
        previewCache.totalCostLimit = 48 * 1_024 * 1_024
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
        currentFrameIndex = selection.lowerBound
        loadPreview()
    }

    func selectFrame(_ index: Int, extending: Bool = false) {
        let index = min(max(0, index), document.frames.count - 1)
        if extending {
            selection = .init(lowerBound: min(selection.lowerBound, index), upperBound: max(selection.upperBound, index + 1))
        } else {
            selection = .init(lowerBound: index, upperBound: index + 1)
        }
        currentFrameIndex = index
        loadPreview()
    }

    func moveSelection(by offset: Int, extending: Bool = false) {
        selectFrame(currentFrameIndex + offset, extending: extending)
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
        let url = document.frames[currentFrameIndex].sourceURL
        let cropKey = document.settings.crop.map { "\($0.x),\($0.y),\($0.width),\($0.height)" } ?? "full"
        let key = "\(url.absoluteString)#\(cropKey)" as NSString
        if let cached = previewCache.object(forKey: key) { previewImage = cached; return }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceThumbnailMaxPixelSize: Self.previewMaximumPixelSize,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            previewImage = nil
            statusMessage = GIFStudioDocumentError.previewUnavailable.localizedDescription
            return
        }
        let displayed: CGImage
        if let crop = document.settings.crop {
            let rect = CGRect(x: crop.x * Double(image.width), y: crop.y * Double(image.height),
                              width: crop.width * Double(image.width), height: crop.height * Double(image.height)).integral
            displayed = image.cropping(to: rect) ?? image
        } else { displayed = image }
        let preview = NSImage(cgImage: displayed, size: .zero)
        previewCache.setObject(preview, forKey: key, cost: image.bytesPerRow * image.height)
        previewImage = preview
    }

    private func trimToSelection() {
        mutate("Trimmed to selection") { try $0.trimmed(to: selection.range) }
        selection = .init(lowerBound: 0, upperBound: document.frames.count)
        currentFrameIndex = 0
        loadPreview()
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
        loadPreview()
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
        loadPreview()
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
            loadPreview()
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
        loadPreview()
    }

    private func redo() {
        guard let next = redoDocuments.popLast() else { return }
        undoDocuments.append(document)
        document = next
        selection = selection.clamped(to: document.frames.count)
        statusMessage = "Redid edit"
        scheduleAutosave()
        loadPreview()
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
