import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Aeroshot

@Suite(.serialized)
@MainActor
struct GIFStudioModelTests {
    @Test func timedAnnotationCommandsEditReorderRevealAndUndo() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: makeFrames(count: 3, in: directory)),
            projectAdapter: .init { _ in }
        )

        model.setSelection(.init(lowerBound: 1, upperBound: 2))
        model.addTimedAnnotation("First")
        let firstID = try #require(model.document.annotations.first?.id)
        model.addTimedAnnotation("Second")
        let secondID = try #require(model.document.annotations.last?.id)
        model.updateAnnotation(firstID, text: "Edited")
        #expect(model.document.annotations.first?.text == "Edited")
        model.moveAnnotation(secondID, by: -1)
        #expect(model.document.annotations.first?.id == secondID)
        model.duplicateAnnotation(firstID)
        #expect(model.document.annotations.count == 3)
        model.selectFrame(0)
        model.revealAnnotation(firstID)
        #expect(model.currentFrameIndex == 1)
        model.deleteAnnotation(secondID)
        #expect(model.document.annotations.count == 2)
        model.perform(.undo)
        #expect(model.document.annotations.contains { $0.id == secondID })
    }

    @Test func closeSavePropagatesWriteFailure() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: makeFrames(count: 1, in: directory)),
            projectAdapter: .init { _ in throw CocoaError(.fileWriteNoPermission) }
        )

        #expect(throws: CocoaError.self) { try model.saveForClose() }
    }

    @Test func commandsAreExactUndoableAndPersistedForReopen() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let frames = try makeFrames(count: 5, in: directory)
        let projectURL = directory.appending(path: "gif-project.json")
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: frames),
            projectAdapter: fileAdapter(projectURL)
        )

        model.setSelection(.init(lowerBound: 1, upperBound: 3))
        model.setSelectedDuration(milliseconds: 75)
        #expect(model.document.frames[1].durationMicroseconds == 75_000)
        #expect(model.document.frames[2].durationMicroseconds == 75_000)
        model.perform(.duplicate)
        #expect(model.document.frames.count == 7)
        #expect(model.document.frames[3].id != model.document.frames[1].id)
        #expect(model.document.frames[3].durationMicroseconds == 75_000)
        model.perform(.undo)
        #expect(model.document.frames.count == 5)
        model.perform(.redo)
        #expect(model.document.frames.count == 7)
        model.saveNow()

        let reopened = try JSONDecoder().decode(GIFDocument.self, from: Data(contentsOf: projectURL))
        #expect(reopened == model.document)
    }

    @Test func selectionCommandsAndSettingsAreDeterministic() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: makeFrames(count: 6, in: directory)),
            projectAdapter: .init { _ in }
        )
        model.setSelection(.init(lowerBound: 2, upperBound: 5))
        model.perform(.trim)
        #expect(model.document.frames.count == 3)
        #expect(model.document.durationMicroseconds == 300_000)
        model.perform(.undo)
        model.setSelection(.init(lowerBound: 2, upperBound: 4))
        model.perform(.delete)
        #expect(model.document.frames.count == 4)
        model.perform(.undo)
        model.setSelection(.init(lowerBound: 3, upperBound: 4))
        model.perform(.split)
        #expect(model.document.frames.count == 3)

        model.updateSettings {
            $0.loop = .count(4); $0.pingPong = true; $0.outputWidth = 80; $0.outputHeight = 40
            $0.paletteSize = 32; $0.dither = .ordered; $0.preservesTransparency = false; $0.quality = 0.4
        }
        #expect(model.document.settings.loop == .count(4))
        #expect(model.document.settings.pingPong)
        #expect(model.document.settings.paletteSize == 32)
        #expect(model.estimatedOutputBytes(sourceSize: CGSize(width: 320, height: 240)) > 0)
        #expect(model.effectiveDelayDescription(for: 10).contains("effective"))
    }

    @Test func longProjectPreviewStateIsDurationIndependent() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "shared.png")
        try writePNG(image(seed: 7), to: source)
        // 600 frames × 100 ms = 60 seconds. Frame metadata remains URL-and-integer-only.
        let frames = try (0..<600).map { _ in try GIFFrame(sourceURL: source, durationMicroseconds: 100_000) }
        let model = GIFStudioDocument(document: try GIFDocument(frames: frames), projectAdapter: .init { _ in })
        #expect(model.document.durationMicroseconds == 60_000_000)
        try await waitUntil { model.previewImage != nil }
        #expect(model.residentDecodedPreviewCount == 1)
        model.selectFrame(599)
        try await waitUntil { model.previewImage != nil }
        #expect(model.residentDecodedPreviewCount == 1)
    }

    @Test func simulatedPlaybackDecouplesPlayheadAndKeepsReadAheadBounded() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: makeFrames(count: 10, in: directory)),
            projectAdapter: .init { _ in }
        )
        model.setSelection(.init(lowerBound: 4, upperBound: 6))
        let editSelection = model.selection
        for timestamp in stride(from: Int64(0), through: 2_000_000, by: 100_000) {
            model.advancePlayback(toWallElapsedMicroseconds: timestamp)
            #expect(model.residentDecodedPreviewCount <= GIFStudioDocument.previewCacheCountLimit)
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(model.selection == editSelection)
        #expect(model.currentFrameIndex != model.selection.lowerBound)
        #expect(model.residentDecodedPreviewCount > 0)
        #expect(model.residentDecodedPreviewCount <= GIFStudioDocument.previewCacheCountLimit)
    }

    @Test func playbackScrubRateAndMutationLifecycleAreDeterministic() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: makeFrames(count: 4, in: directory)),
            projectAdapter: .init { _ in }
        )
        model.setPlaybackRate(.double)
        model.scrub(to: 0.5)
        #expect(model.playbackRate == .double)
        #expect(model.currentFrameIndex == 2)
        #expect(!model.isPlaying)
        model.beginScrubbing()
        model.scrub(to: 0.75)
        model.endScrubbing()
        #expect(!model.isPlaying)
        model.play()
        #expect(model.isPlaying)
        model.play()
        #expect(model.isPlaying)
        model.beginScrubbing()
        #expect(!model.isPlaying)
        model.scrub(to: 0.25)
        model.endScrubbing()
        #expect(model.isPlaying)
        model.updateSettings { $0.pingPong = true }
        #expect(!model.isPlaying)
        #expect(model.playbackPositionMicroseconds < model.playbackDurationMicroseconds)
        model.pausePlayback()
        #expect(!model.isPlaying)
    }

    @Test func editedDurationsDriveOneTimesPlaybackAndFiniteCompletionExactly() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: makeFrames(count: 3, in: directory)),
            projectAdapter: .init { _ in }
        )
        model.setSelection(.init(lowerBound: 0, upperBound: 1))
        model.setSelectedDuration(milliseconds: 17)
        model.setSelection(.init(lowerBound: 1, upperBound: 2))
        model.setSelectedDuration(milliseconds: 29)
        model.updateSettings { $0.loop = .once }

        model.advancePlayback(toWallElapsedMicroseconds: 16_999)
        #expect(model.currentFrameIndex == 0)
        model.advancePlayback(toWallElapsedMicroseconds: 17_000)
        #expect(model.currentFrameIndex == 1)
        model.advancePlayback(toWallElapsedMicroseconds: 46_000)
        #expect(model.currentFrameIndex == 2)
        model.advancePlayback(toWallElapsedMicroseconds: 146_000)
        #expect(model.currentFrameIndex == 2)
        #expect(model.playbackPositionMicroseconds == 146_000)
    }

    @Test func monotonicPauseResumeOvershootAndFiniteTaskSettlingDoNotDrift() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = MonotonicTestClock()
        var settings = GIFExportSettings()
        settings.loop = .once
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: makeFrames(count: 3, in: directory), settings: settings),
            projectAdapter: .init { _ in },
            monotonicNowNanoseconds: { now.value }
        )

        model.play()
        model.play()
        now.value = 50_000_000
        _ = model.servicePlaybackTickForTesting()
        model.pausePlayback()
        model.pausePlayback()
        #expect(model.playbackPositionMicroseconds == 50_000)

        now.value = 1_000_000_000
        model.play()
        now.value = 1_175_000_000
        _ = model.servicePlaybackTickForTesting()
        #expect(model.currentFrameIndex == 2)
        #expect(model.playbackPositionMicroseconds == 225_000)

        now.value = 1_300_000_000
        _ = model.servicePlaybackTickForTesting()
        #expect(!model.isPlaying)
        #expect(model.currentFrameIndex == 2)
        #expect(model.playbackPositionMicroseconds == 300_000)

        model.play()
        model.updateSettings { $0.loop = .count(2) }
        #expect(!model.isPlaying)
        model.perform(.undo)
        #expect(model.document.settings.loop == .once)
        #expect(!model.isPlaying)
        model.perform(.redo)
        #expect(model.document.settings.loop == .count(2))
        #expect(!model.isPlaying)
    }

    @Test func stalePreviewDecodeCannotReplaceNewerSeekAndCacheHitsDedupe() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let frames = try makeFrames(count: 4, in: directory)
        let probe = PreviewDecodeProbe()
        let decoder = GIFPreviewDecoder { key in await probe.decode(key) }
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: frames),
            projectAdapter: .init { _ in },
            previewDecoder: decoder
        )

        model.selectFrame(3)
        try await waitUntil { model.previewImage != nil }
        #expect(model.currentFrameIndex == 3)
        #expect(model.previewImage?.size.width == 5)
        try await Task.sleep(for: .milliseconds(180))
        #expect(model.previewImage?.size.width == 5)
        #expect(model.residentDecodedPreviewCount <= GIFStudioDocument.previewCacheCountLimit)

        let before = await probe.decodeCount(for: frames[3].sourceURL)
        model.selectFrame(3)
        try await Task.sleep(for: .milliseconds(20))
        #expect(await probe.decodeCount(for: frames[3].sourceURL) == before)
    }

    @Test func fullPreviewCacheAdmitsSeventhCurrentFrameAndEvictsLRU() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let frames = try makeFrames(count: 7, in: directory)
        let probe = PreviewDecodeProbe()
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: frames),
            projectAdapter: .init { _ in },
            previewDecoder: .init { key in await probe.decode(key) }
        )

        model.selectFrame(3)
        try await waitUntil { model.residentDecodedPreviewCount == GIFStudioDocument.previewCacheCountLimit }
        model.selectFrame(6)
        try await waitUntil { model.previewImage?.size.width == 8 }
        #expect(model.currentFrameIndex == 6)
        #expect(model.residentDecodedPreviewCount <= GIFStudioDocument.previewCacheCountLimit)
    }

    @Test func doubleRateSeekAtOddBoundaryIsExactAndCropInvalidatesPreview() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let frames = try makeFrames(count: 2, in: directory).enumerated().map { index, frame in
            try GIFFrame(id: frame.id, sourceURL: frame.sourceURL, durationMicroseconds: index == 0 ? 16_667 : 20_001)
        }
        let model = GIFStudioDocument(document: try GIFDocument(frames: frames), projectAdapter: .init { _ in })
        try await waitUntil { model.previewImage != nil }
        model.setPlaybackRate(.double)
        model.selectFrame(1)
        #expect(model.currentFrameIndex == 1)
        try await waitUntil { model.previewImage != nil }
        let fullWidth = try #require(model.previewImage).size.width
        model.updateSettings { $0.crop = .init(x: 0, y: 0, width: 0.5, height: 1) }
        #expect(model.previewImage == nil)
        try await waitUntil { model.previewImage != nil }
        #expect(try #require(model.previewImage).size.width < fullWidth)
    }

    @Test func foreverPlaybackTaskDoesNotRetainDocument() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var model: GIFStudioDocument? = GIFStudioDocument(
            document: try GIFDocument(frames: makeFrames(count: 2, in: directory)),
            projectAdapter: .init { _ in }
        )
        weak var weakModel = model
        model?.play()
        model = nil
        for _ in 0..<20 where weakModel != nil { await Task.yield() }
        #expect(weakModel == nil)
    }

    @Test func modelPerformsRealSmallAtomicExport() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: makeFrames(count: 3, in: directory)),
            projectAdapter: .init { _ in }
        )
        let output = directory.appending(path: "studio-export.gif")
        model.export(to: output)
        try await waitUntil { model.exportProgress == nil }
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "com.compuserve.gif")
        #expect(CGImageSourceGetCount(source) == 3)
        #expect(model.lastExportURL == output)
        #expect((model.lastExportMetadata?.byteCount ?? 0) > 0)
    }

    @Test func controllerUsesProjectBridgeForImportSaveAndReopen() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceGIF = directory.appending(path: "source.gif")
        let sourceDocument = try GIFDocument(frames: makeFrames(count: 3, in: directory))
        _ = try await GIFWriter().write(sourceDocument, to: sourceGIF)
        let package = directory.appending(path: "editable.aeroshot")

        let model = try GIFStudioDocument.create(from: sourceGIF, packageURL: package)
        model.setSelection(.init(lowerBound: 0, upperBound: 2))
        model.setSelectedDuration(milliseconds: 44)
        model.updateSettings { $0.loop = .count(5); $0.paletteSize = 64 }
        model.saveNow()
        let reopened = try GIFStudioDocument.open(packageURL: package)

        #expect(reopened.document == model.document)
        #expect(reopened.document.frames[0].durationMicroseconds == 44_000)
        #expect(reopened.document.settings.loop == .count(5))
        #expect(reopened.document.settings.paletteSize == 64)
    }

    @Test func undoHistoryIsBoundedAndDropsOldestFirst() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: makeFrames(count: 2, in: directory)),
            projectAdapter: .init { _ in }
        )

        let baseline = model.document.frames.count
        let extra = 10
        model.setSelection(.init(lowerBound: 0, upperBound: 1))
        for _ in 0..<(GIFStudioDocument.undoDepthLimit + extra) {
            model.perform(.duplicate)
        }
        #expect(model.document.frames.count == baseline + GIFStudioDocument.undoDepthLimit + extra)

        var undoCount = 0
        while model.canUndo {
            model.perform(.undo)
            undoCount += 1
        }
        #expect(undoCount == GIFStudioDocument.undoDepthLimit)
        // The oldest `extra` duplications were evicted, so they are unrecoverable.
        #expect(model.document.frames.count == baseline + extra)
    }

    @Test func continuousSettingsPreviewCommitsOneExactUndoOrCancelsWithoutOne() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = GIFStudioDocument(
            document: try GIFDocument(frames: makeFrames(count: 2, in: directory)),
            projectAdapter: .init { _ in }
        )
        let original = model.document

        model.beginContinuousEdit()
        for index in 1...100 { model.previewSettings { $0.quality = Double(index) / 200 } }
        #expect(model.commitContinuousEdit())
        let final = model.document
        #expect(final.settings.quality == 0.5)
        model.perform(.undo)
        #expect(model.document == original)
        model.perform(.redo)
        #expect(model.document == final)

        let clean = GIFStudioDocument(document: original, projectAdapter: .init { _ in })
        clean.beginContinuousEdit()
        clean.previewSettings { $0.quality = 0.25 }
        clean.cancelContinuousEdit()
        #expect(clean.document == original)
        #expect(!clean.canUndo)
        clean.beginContinuousEdit()
        #expect(!clean.commitContinuousEdit())
        #expect(!clean.canUndo)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for GIF Studio operation")
    }

    private func fileAdapter(_ url: URL) -> GIFStudioProjectAdapter {
        .init { document in try JSONEncoder().encode(document).write(to: url, options: .atomic) }
    }

    private func makeFrames(count: Int, in directory: URL) throws -> [GIFFrame] {
        try (0..<count).map { index in
            let url = directory.appending(path: "frame-\(index).png")
            try writePNG(image(seed: UInt8(index + 1)), to: url)
            return try GIFFrame(sourceURL: url, durationMicroseconds: 100_000)
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Aeroshot-GIF-Model-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func image(seed: UInt8) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 24, height: 18, bitsPerComponent: 8, bytesPerRow: 96,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: CGFloat(seed) / 16, green: 0.3, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 18))
        return try #require(context.makeImage())
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

}

private actor PreviewDecodeProbe {
    private var counts: [URL: Int] = [:]

    func decode(_ key: GIFPreviewKey) async -> GIFDecodedPreview? {
        counts[key.sourceURL, default: 0] += 1
        let index = Int(key.sourceURL.deletingPathExtension().lastPathComponent.split(separator: "-").last ?? "0") ?? 0
        try? await Task.sleep(for: .milliseconds(index == 0 ? 140 : (index == 3 ? 10 : 30)))
        let width = index + 2
        guard let context = CGContext(
            data: nil, width: width, height: 2, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let red = index == 3 ? 240 : UInt8(20 + index)
        context.setFillColor(CGColor(red: CGFloat(red) / 255, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 2))
        guard let image = context.makeImage() else { return nil }
        return .init(image: image, cost: 16)
    }

    func decodeCount(for url: URL) -> Int { counts[url, default: 0] }
}

@MainActor
private final class MonotonicTestClock {
    var value: UInt64 = 0
}
