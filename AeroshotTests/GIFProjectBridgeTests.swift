import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Aeroshot

@Suite(.serialized)
struct GIFProjectBridgeTests {
    @Test func allEditsAndSettingsSurviveReopenExactly() throws {
        try withFixture { source, package in
            let originalBytes = try Data(contentsOf: source)
            let imported = try GIFProjectBridge.importSource(from: source, to: package)
            let originalAsset = try #require(imported.assets.first)
            var document = try GIFProjectBridge.open(from: package)

            document = try document.trimmed(to: try GIFTimeRange(
                startMicroseconds: 33_333, durationMicroseconds: 166_667
            ))
            document.frames[0].durationMicroseconds = 12_345
            document.frames[1].durationMicroseconds = 67_891
            document.settings = GIFExportSettings(
                loop: .count(7), pingPong: true,
                outputWidth: 321, outputHeight: 123,
                paletteSize: 17, dither: .ordered,
                preservesTransparency: false, quality: 0.73123456789,
                crop: .init(x: 0.1, y: 0.2, width: 0.8, height: 0.7)
            )
            document.annotations = [.init(range: try GIFTimeRange(startMicroseconds: 1_000, durationMicroseconds: 10_000), text: "Inspect")]

            let expectedIDs = document.frames.map(\.id)
            let expectedDurations = document.frames.map(\.durationMicroseconds)
            _ = try GIFProjectBridge.save(document, to: package)
            let reopened = try GIFProjectBridge.open(from: package)
            #expect(reopened.frames.map(\.id) == expectedIDs)
            #expect(reopened.frames.map(\.durationMicroseconds) == expectedDurations)
            #expect(reopened.settings == document.settings)
            #expect(reopened.annotations == document.annotations)
            #expect(reopened.estimatedOutputBytes(sourceSize: CGSize(width: 3, height: 2))
                    == document.estimatedOutputBytes(sourceSize: CGSize(width: 3, height: 2)))

            let savedAsset = try #require(AeroProjectPackageStore(packageURL: package).load().assets.first)
            #expect(savedAsset == originalAsset)
            #expect(savedAsset.sha256 == AeroProjectPackageStore.sha256(of: originalBytes))
            #expect(try Data(contentsOf: package.appending(path: savedAsset.relativePath)) == originalBytes)
        }
    }

    @Test func everyLoopVariantRoundTrips() throws {
        try withFixture { source, package in
            _ = try GIFProjectBridge.importSource(from: source, to: package)
            for loop in [GIFLoop.once, .count(23), .forever] {
                var document = try GIFProjectBridge.open(from: package)
                document.settings.loop = loop
                _ = try GIFProjectBridge.save(document, to: package)
                #expect(try GIFProjectBridge.open(from: package).settings.loop == loop)
            }
        }
    }

    @Test func legacyGIFStateUsesDefaultsWithoutChangingScreenshotSchema() throws {
        try withFixture { source, package in
            var manifest = try GIFProjectBridge.importSource(from: source, to: package)
            manifest.gifEditState = nil
            try writeManifest(manifest, package: package)
            try? FileManager.default.removeItem(at: package.appending(path: "generated/gif-frames"))

            let opened = try GIFProjectBridge.open(from: package)
            #expect(opened.settings == GIFExportSettings())
            // ImageIO represents GIF delays in centiseconds.
            #expect(opened.frames.map(\.durationMicroseconds) == [30_000, 70_000, 100_000])
            #expect(try AeroProjectPackageStore(packageURL: package).load().gifEditState == nil)

            let screenshot = AeroProjectManifest(editorCropRectPixels: AeroRect(x: 1, y: 2, width: 3, height: 4))
            var object = try #require(JSONSerialization.jsonObject(with: AeroProjectMigrator.encode(screenshot)) as? [String: Any])
            object.removeValue(forKey: "gifEditState")
            let decoded = try AeroProjectMigrator.decodeAndMigrate(JSONSerialization.data(withJSONObject: object))
            #expect(decoded.gifEditState == nil)
            #expect(decoded.editorCropRectPixels == screenshot.editorCropRectPixels)
        }
    }

    @Test func missingGeneratedFramesRebuildFromImmutableOriginal() throws {
        try withFixture { source, package in
            _ = try GIFProjectBridge.importSource(from: source, to: package)
            var document = try GIFProjectBridge.open(from: package).trimmed(to: 1..<3)
            try document.setDuration(54_321, for: 0..<document.frames.count)
            _ = try GIFProjectBridge.save(document, to: package)
            let checksum = try #require(AeroProjectPackageStore(packageURL: package).load().assets.first).sha256
            try FileManager.default.removeItem(at: package.appending(path: "generated/gif-frames"))

            let rebuilt = try GIFProjectBridge.open(from: package)
            #expect(rebuilt.frames.map(\.durationMicroseconds) == [54_321, 54_321])
            #expect(try #require(AeroProjectPackageStore(packageURL: package).load().assets.first).sha256 == checksum)
            #expect(rebuilt.frames.allSatisfy { FileManager.default.fileExists(atPath: $0.sourceURL.path) })
        }
    }

    @Test func missingCorruptWrongAndMutableSourcesAreRejected() throws {
        try withFixture { source, package in
            var manifest = try GIFProjectBridge.importSource(from: source, to: package)
            let asset = try #require(manifest.assets.first)
            let assetURL = package.appending(path: asset.relativePath)
            try FileManager.default.removeItem(at: assetURL)
            #expect(throws: AeroProjectPackageError.missingAsset(asset.id)) {
                try GIFProjectBridge.open(from: package)
            }

            try Data("bad".utf8).write(to: assetURL)
            #expect(throws: AeroProjectPackageError.byteCountMismatch(asset.id)) {
                try GIFProjectBridge.open(from: package)
            }

            try Data(contentsOf: source).write(to: assetURL)
            var metadata = asset.metadata
            metadata.mediaType = .image
            manifest.assets[0] = AeroProjectAsset(
                id: asset.id, relativePath: asset.relativePath, sha256: asset.sha256,
                byteCount: asset.byteCount, isImmutableOriginal: true, metadata: metadata
            )
            try writeManifest(manifest, package: package)
            #expect(throws: GIFProjectBridgeError.wrongSourceMediaType(asset.id, .image)) {
                try GIFProjectBridge.open(from: package)
            }

            manifest.assets[0] = AeroProjectAsset(
                id: asset.id, relativePath: asset.relativePath, sha256: asset.sha256,
                byteCount: asset.byteCount, isImmutableOriginal: false, metadata: asset.metadata
            )
            try writeManifest(manifest, package: package)
            #expect(throws: GIFProjectBridgeError.sourceIsNotImmutable(asset.id)) {
                try GIFProjectBridge.open(from: package)
            }
        }
    }

    @Test func malformedStateFailsTypedValidation() throws {
        let id = UUID()
        let frame = AeroGIFEditState.Frame(
            id: id, generatedRelativePath: "generated/gif-frames/frame.png", durationMicroseconds: 1
        )
        #expect(throws: AeroGIFEditStateError.noFrames) { try AeroGIFEditState(frames: []) }
        #expect(throws: AeroGIFEditStateError.duplicateFrameID(id)) {
            try AeroGIFEditState(frames: [frame, frame])
        }
        #expect(throws: AeroGIFEditStateError.invalidFrameDuration(id)) {
            try AeroGIFEditState(frames: [.init(id: id, generatedRelativePath: frame.generatedRelativePath, durationMicroseconds: 0)])
        }
        #expect(throws: AeroGIFEditStateError.invalidFramePath("assets/originals/source.gif")) {
            try AeroGIFEditState(frames: [.init(id: id, generatedRelativePath: "assets/originals/source.gif", durationMicroseconds: 1)])
        }
        #expect(throws: AeroGIFEditStateError.invalidLoopCount) {
            try AeroGIFEditState(frames: [frame], loop: .count(0))
        }
        #expect(throws: AeroGIFEditStateError.invalidOutputDimensions) {
            try AeroGIFEditState(frames: [frame], outputWidth: 0)
        }
        #expect(throws: AeroGIFEditStateError.invalidPaletteSize) {
            try AeroGIFEditState(frames: [frame], paletteSize: 257)
        }
        #expect(throws: AeroGIFEditStateError.invalidQuality) {
            try AeroGIFEditState(frames: [frame], quality: .infinity)
        }
        #expect(throws: AeroGIFEditStateError.invalidSpoolLimits) {
            try AeroGIFEditState(frames: [frame], spoolMaximumFrameCount: 0)
        }
    }

    @Test func boundedImportAndUnsupportedInputAreRejected() throws {
        try withFixture { source, package in
            #expect(throws: GIFProjectBridgeError.generatedCacheLimitExceeded) {
                try GIFProjectBridge.importSource(
                    from: source, to: package,
                    limits: .init(maximumFrameCount: 2, maximumBytes: 1_000_000)
                )
            }
            let text = package.deletingLastPathComponent().appending(path: "not-gif.txt")
            try Data("hello".utf8).write(to: text)
            #expect(throws: GIFProjectBridgeError.unsupportedSourceType) {
                try GIFProjectBridge.importSource(from: text, to: package)
            }
        }
    }

    private func withFixture(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GIFProjectBridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source.gif")
        try makeGIF(at: source)
        try body(source, root.appending(path: "project.aeroshot"))
    }

    private func makeGIF(at url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 3, nil)
        else { throw FixtureError.failed }
        for (index, microseconds) in [33_333, 66_667, 100_000].enumerated() {
            guard let context = CGContext(
                data: nil, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 12,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw FixtureError.failed }
            context.setFillColor(CGColor(red: CGFloat(index) / 3, green: 0.25, blue: 0.75, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
            guard let image = context.makeImage() else { throw FixtureError.failed }
            let delay = Double(microseconds) / 1_000_000
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFUnclampedDelayTime: delay,
                kCGImagePropertyGIFDelayTime: delay,
            ]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.failed }
    }

    private func writeManifest(_ manifest: AeroProjectManifest, package: URL) throws {
        try AeroProjectMigrator.encode(manifest).write(
            to: package.appending(path: AeroProjectPackageStore.manifestFileName), options: .atomic
        )
    }

    private enum FixtureError: Error { case failed }
}
