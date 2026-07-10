import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Aeroshot

@Suite(.serialized)
struct GIFStudioTests {
    @Test func exactTimingAndEditsRoundTrip() throws {
        let urls = (0..<4).map { URL(fileURLWithPath: "/tmp/frame-" + String($0) + ".png") }
        var document = try GIFDocument(frames: try urls.enumerated().map {
            try GIFFrame(sourceURL: $0.element, durationMicroseconds: Int64(($0.offset + 1) * 16_667))
        })
        try document.setDuration(25_000, for: 1..<3)
        try document.duplicateFrame(at: 2)
        try document.deleteFrame(at: 0)
        let trimmed = try document.trimmed(to: 1..<4)
        let (left, right) = try trimmed.split(at: 1)
        #expect(left.durationMicroseconds + right.durationMicroseconds == trimmed.durationMicroseconds)
        let exactRange = try GIFTimeRange(startMicroseconds: 10_000, durationMicroseconds: 50_000)
        let exactTrim = try document.trimmed(to: exactRange)
        #expect(exactTrim.durationMicroseconds == 50_000)
        let exactSplit = try document.split(atMicroseconds: 12_345)
        #expect(exactSplit.0.durationMicroseconds == 12_345)
        #expect(exactSplit.0.durationMicroseconds + exactSplit.1.durationMicroseconds == document.durationMicroseconds)
        var exactDelete = document
        try exactDelete.delete(try GIFTimeRange(startMicroseconds: 12_345, durationMicroseconds: 22_222))
        #expect(exactDelete.durationMicroseconds == document.durationMicroseconds - 22_222)
        let data = try JSONEncoder().encode(document)
        #expect(try JSONDecoder().decode(GIFDocument.self, from: data) == document)
    }

    @Test func spoolIsBoundedAndNeverRetainsDecodedFrames() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try generatedImage(seed: 1)
        let spool = try GIFFrameSpool(
            directoryURL: directory,
            limits: .init(maximumFrameCount: 3, maximumBytes: 10_000_000)
        )
        for _ in 0..<600 { _ = try spool.append(image, durationMicroseconds: 100_000) }
        #expect(spool.statistics.frameCount == 3)
        #expect(spool.statistics.residentDecodedFrameCount == 0)
        #expect((try FileManager.default.contentsOfDirectory(atPath: directory.path)).count == 3)
        spool.removeAll()
        #expect((try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty)
    }

    @Test func spoolByteBoundRejectsAndDeletesOverflowFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let spool = try GIFFrameSpool(directoryURL: directory, limits: .init(maximumFrameCount: 10, maximumBytes: 1))
        #expect(try spool.append(generatedImage(seed: 2), durationMicroseconds: 50_000) == false)
        #expect(spool.statistics == .init(frameCount: 0, byteCount: 0))
        #expect((try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty)
    }

    @Test func abandonedSpoolRecoveryIsScoped() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let abandoned = root.appending(path: "Aeroshot-GIF-Spool-abandoned")
        let unrelated = root.appending(path: "keep-me")
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        GIFFrameSpool.recoverAbandonedSpools(in: root, olderThan: 0)
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test func writerPreservesSubHundredMillisecondTimingLoopResizeAndCoalescing() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "first.png")
        let duplicate = directory.appending(path: "duplicate.png")
        let second = directory.appending(path: "second.png")
        try writePNG(generatedImage(seed: 3), to: first)
        try FileManager.default.copyItem(at: first, to: duplicate)
        try writePNG(generatedImage(seed: 4), to: second)
        var settings = GIFExportSettings()
        settings.loop = .count(3)
        settings.outputWidth = 16
        settings.outputHeight = 12
        settings.paletteSize = 16
        settings.dither = .ordered
        settings.quality = 0.5
        let document = try GIFDocument(frames: [
            try GIFFrame(sourceURL: first, durationMicroseconds: 20_000),
            try GIFFrame(sourceURL: duplicate, durationMicroseconds: 30_000),
            try GIFFrame(sourceURL: second, durationMicroseconds: 40_000),
        ], settings: settings)
        let output = directory.appending(path: "result.gif")
        let metadata = try await GIFWriter().write(document, to: output)
        #expect(metadata.frameCount == 2)
        #expect(metadata.coalescedFrameCount == 1)
        #expect(metadata.durationMicroseconds == 90_000)
        #expect(metadata.imageIOLoopCount == 3)
        #expect(metadata.outputSize == CGSize(width: 16, height: 12))

        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        let fileProperties = try #require(CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
        let gif = try #require(fileProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        #expect(gif[kCGImagePropertyGIFLoopCount] as? Int == 3)
        let frameProperties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let frameGIF = try #require(frameProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        #expect(abs((frameGIF[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0) - 0.05) < 0.001)
        let outputImage = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(outputImage.width == 16)
        #expect(outputImage.height == 12)
    }

    @Test func pingPongAndSizeEstimateAreDeterministic() throws {
        let frames = try (0..<4).map {
            try GIFFrame(sourceURL: URL(fileURLWithPath: "/tmp/" + String($0) + ".png"), durationMicroseconds: 100_000)
        }
        var settings = GIFExportSettings()
        settings.pingPong = true
        settings.paletteSize = 32
        settings.outputWidth = 80
        settings.outputHeight = 40
        let document = try GIFDocument(frames: frames, settings: settings)
        let estimate = document.estimatedOutputBytes(sourceSize: CGSize(width: 640, height: 480))
        #expect(estimate > 0)
        #expect(estimate == document.estimatedOutputBytes(sourceSize: CGSize(width: 640, height: 480)))
        #expect(GIFLoop.once.imageIOLoopCount == 1)
        #expect(GIFLoop.count(7).imageIOLoopCount == 7)
        #expect(GIFLoop.forever.imageIOLoopCount == 0)
    }

    @Test func documentationAndSocialPresetsAreDistinctAndStable() throws {
        let base = GIFExportSettings()
        let documentation = GIFExportPreset.documentation.applying(to: base)
        let social = GIFExportPreset.social.applying(to: base)
        #expect(documentation.paletteSize == 128)
        #expect(documentation.preservesTransparency)
        #expect(social.paletteSize == 64)
        #expect(social.dither == .ordered)
        #expect(!social.preservesTransparency)
        #expect(social.outputWidth == 1_280)
    }

    @Test func cropSpeedAndTimedAnnotationsRoundTripAndExport() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let frame = directory.appending(path: "frame.png")
        try writePNG(generatedImage(seed: 8, width: 40, height: 20), to: frame)
        var settings = GIFExportSettings()
        settings.crop = .init(x: 0.25, y: 0, width: 0.5, height: 1)
        var document = try GIFDocument(frames: [
            try GIFFrame(sourceURL: frame, durationMicroseconds: 100_000),
            try GIFFrame(sourceURL: frame, durationMicroseconds: 100_000),
        ], settings: settings, annotations: [
            .init(range: try GIFTimeRange(startMicroseconds: 0, durationMicroseconds: 100_000), text: "Focus")
        ])
        try document.applySpeed(2, to: 0..<1)
        #expect(document.frames[0].durationMicroseconds == 50_000)
        #expect(try JSONDecoder().decode(GIFDocument.self, from: JSONEncoder().encode(document)) == document)
        let output = directory.appending(path: "edited.gif")
        let metadata = try await GIFWriter().write(document, to: output)
        #expect(metadata.frameCount == 2)
        #expect(metadata.outputSize == CGSize(width: 40, height: 20))
    }

    @Test func transparencyMetadataSurvivesExport() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appending(path: "transparent.png")
        let outputURL = directory.appending(path: "transparent.gif")
        try writePNG(try transparentImage(), to: frameURL)
        var settings = GIFExportSettings()
        settings.preservesTransparency = true
        let document = try GIFDocument(
            frames: [try GIFFrame(sourceURL: frameURL, durationMicroseconds: 100_000)],
            settings: settings
        )
        _ = try await GIFWriter().write(document, to: outputURL)
        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyHasAlpha] as? Bool == true)
    }

    @Test func cancellationPreservesExistingDestinationAndRemovesPartial() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "frame.png")
        try writePNG(generatedImage(seed: 5), to: source)
        let output = directory.appending(path: "result.gif")
        let sentinel = Data("existing".utf8)
        try sentinel.write(to: output)
        let document = try GIFDocument(frames: [try GIFFrame(sourceURL: source, durationMicroseconds: 50_000)])
        let task = Task { try await GIFWriter().write(document, to: output) }
        task.cancel()
        await #expect(throws: GIFCoreError.cancelled) { try await task.value }
        #expect(try Data(contentsOf: output) == sentinel)
        #expect((try FileManager.default.contentsOfDirectory(atPath: directory.path)).allSatisfy { !$0.contains(".partial-") })
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Aeroshot-GIF-Test-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func generatedImage(seed: UInt8, width: Int = 32, height: Int = 24) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: CGFloat(seed) / 255, green: 0.25, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: CGFloat(seed) / 255, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: Int(seed) % 8, y: 3, width: 12, height: 10))
        return try #require(context.makeImage())
    }

    private func transparentImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.clear(CGRect(x: 0, y: 0, width: 8, height: 8))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 2, y: 2, width: 4, height: 4))
        return try #require(context.makeImage())
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
