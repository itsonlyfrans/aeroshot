import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Aeroshot

@Suite(.serialized)
@MainActor
struct GIFStudioModelTests {
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

    @Test func longProjectPreviewStateIsDurationIndependent() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "shared.png")
        try writePNG(image(seed: 7), to: source)
        // 600 frames × 100 ms = 60 seconds. Frame metadata remains URL-and-integer-only.
        let frames = try (0..<600).map { _ in try GIFFrame(sourceURL: source, durationMicroseconds: 100_000) }
        let model = GIFStudioDocument(document: try GIFDocument(frames: frames), projectAdapter: .init { _ in })
        #expect(model.document.durationMicroseconds == 60_000_000)
        #expect(model.previewImage != nil)
        #expect(model.residentDecodedPreviewCount == GIFStudioDocument.previewCacheCountLimit)
        model.selectFrame(599)
        #expect(model.previewImage != nil)
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
