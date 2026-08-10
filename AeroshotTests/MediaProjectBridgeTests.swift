import AVFoundation
import CoreVideo
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Aeroshot

@Suite(.serialized)
struct MediaProjectBridgeTests {
    @Test func mp4RoundTripPreservesEditsPresetsAndOriginal() async throws {
        try await withFixture(kind: .mp4) { source, package in
            let sourceBytes = try Data(contentsOf: source)
            let sidecar = RecordingEffectSidecar(events: [
                .init(kind: .cursor, timeMicroseconds: 10_000, x: 0.25, y: 0.75),
                .init(kind: .click, timeMicroseconds: 20_000, x: 0.5, y: 0.5),
            ])
            try JSONEncoder().encode(sidecar).write(to: RecordingEffectEventRecorder.sidecarURL(for: source))
            let imported = try await MediaProjectBridge.importSource(from: source, to: package)
            let asset = try #require(imported.assets.first)
            var document = try MediaProjectBridge.open(from: package)
            let originalDuration = document.composition.duration
            document.composition = try document.composition
                .deleteSelectedRange(.init(start: t(1, 30), duration: t(2, 30)))
                .trim(to: .init(start: .zero, duration: t(7, 30)))
                .split(at: t(3, 30))
            document.composition.overlays = [TimedOverlay(
                id: fixedID(2), kind: .callout,
                range: .init(start: t(1, 30), duration: t(2, 30)), payload: "Inspect",
                bounds: .init(x: 0.42, y: 0.31, width: 0.28, height: 0.22),
                color: .init(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.65)
            )]
            document.composition.canvas = CanvasState(
                crop: .init(x: 0.1, y: 0.2, width: 0.7, height: 0.6), width: 320, height: 240
            )
            document.composition.audio = .init(isMuted: true, gain: 0.625, fadeIn: t(1, 30), fadeOut: t(2, 30))
            #expect(document.composition.effects.events == sidecar.events)
            document.composition.effects.cursorEmphasis = 1.25
            document.composition.effects.clickEmphasis = 0.75
            document.composition.effects.freezeFrame = .init(timeMicroseconds: 20_000, durationMicroseconds: 1_000_000)
            document.composition.effects.reframeAspectRatio = "1:1"
            document.composition.effects.punchInClickTimes = [20_000]
            document.composition.effects.clickSound = "snug_click"
            document.exportPresets = [.init(
                id: fixedID(3), name: "Review",
                preset: MediaExportPreset(
                    codec: .hevc,
                    pixelSize: try AeroPixelSize(width: 320, height: 240),
                    frameRate: try AeroMediaTime(value: 30_000, timescale: 1_001),
                    targetBitRate: 777_777
                )
            )]

            _ = try MediaProjectBridge.save(document, to: package)
            let reopened = try MediaProjectBridge.open(from: package)
            #expect(reopened == document)
            #expect(reopened.composition.duration < originalDuration)
            #expect(reopened.composition.slices.count == 3)
            let savedAsset = try #require(AeroProjectPackageStore(packageURL: package).load().assets.first)
            #expect(savedAsset == asset)
            #expect(savedAsset.sha256 == AeroProjectPackageStore.sha256(of: sourceBytes))
            #expect(try Data(contentsOf: package.appending(path: savedAsset.relativePath)) == sourceBytes)
        }
    }

    @Test func gifRoundTripIsEditableAndByteExact() async throws {
        try await withFixture(kind: .gif) { source, package in
            let bytes = try Data(contentsOf: source)
            let manifest = try await MediaProjectBridge.importSource(from: source, to: package)
            let asset = try #require(manifest.assets.first)
            #expect(asset.metadata.mediaType == .gif)
            // ImageIO canonicalizes the fixture's two short delays to 50 ms.
            let expectedDuration = try AeroMediaTime(value: 1, timescale: 10)
            #expect(asset.metadata.duration == expectedDuration)
            var document = try MediaProjectBridge.open(from: package)
            document.composition = try document.composition.split(at: t(1, 10))
            _ = try MediaProjectBridge.save(document, to: package)
            #expect(try MediaProjectBridge.open(from: package) == document)
            #expect(try Data(contentsOf: package.appending(path: asset.relativePath)) == bytes)
        }
    }

    @Test func missingCorruptAndWrongTypeSourcesAreRejected() async throws {
        try await withFixture(kind: .gif) { source, package in
            var manifest = try await MediaProjectBridge.importSource(from: source, to: package)
            let asset = try #require(manifest.assets.first)
            let assetURL = package.appending(path: asset.relativePath)
            try FileManager.default.removeItem(at: assetURL)
            #expect(throws: AeroProjectPackageError.missingAsset(asset.id)) {
                try MediaProjectBridge.open(from: package)
            }

            try Data("corrupt".utf8).write(to: assetURL)
            #expect(throws: AeroProjectPackageError.byteCountMismatch(asset.id)) {
                try MediaProjectBridge.open(from: package)
            }

            try Data(contentsOf: source).write(to: assetURL)
            manifest.assets[0] = AeroProjectAsset(
                id: asset.id, relativePath: asset.relativePath, sha256: asset.sha256,
                byteCount: asset.byteCount, isImmutableOriginal: true,
                metadata: AeroMediaMetadata(
                    mediaType: .image, pixelSize: asset.metadata.pixelSize,
                    duration: asset.metadata.duration, nominalFrameRate: nil,
                    colorSpaceName: nil, hasAudio: false
                )
            )
            try writeManifest(manifest, package: package)
            #expect(throws: MediaProjectBridgeError.wrongSourceMediaType(asset.id, .image)) {
                try MediaProjectBridge.open(from: package)
            }
        }
    }

    @Test func invalidRangesDurationAndPresetAreRejected() async throws {
        try await withFixture(kind: .gif) { source, package in
            var manifest = try await MediaProjectBridge.importSource(from: source, to: package)
            manifest.mediaComposition?.slices[0].sourceRange = try AeroMediaTimeRange(
                start: .zero, duration: AeroMediaTime(value: 2, timescale: 1)
            )
            try writeManifest(manifest, package: package)
            #expect(throws: MediaProjectBridgeError.invalidComposition([.sourceRangeOutsideAsset(sliceIndex: 0)])) {
                try MediaProjectBridge.open(from: package)
            }

            manifest.assets[0] = replacingDuration(in: manifest.assets[0], with: nil)
            try writeManifest(manifest, package: package)
            #expect(throws: MediaProjectBridgeError.invalidSourceDuration) {
                try MediaProjectBridge.open(from: package)
            }
        }
    }

    @Test func screenshotManifestWithoutMediaFieldsStillRoundTrips() throws {
        let original = AeroProjectManifest(editorCropRectPixels: AeroRect(x: 1, y: 2, width: 3, height: 4))
        var object = try #require(JSONSerialization.jsonObject(with: AeroProjectMigrator.encode(original)) as? [String: Any])
        object.removeValue(forKey: "mediaComposition")
        let decoded = try AeroProjectMigrator.decodeAndMigrate(JSONSerialization.data(withJSONObject: object))
        #expect(decoded.mediaComposition == nil)
        #expect(decoded.editorCropRectPixels == original.editorCropRectPixels)
    }

    @Test func schemaOneMediaOverlayMigratesHistoricalVisualDefaults() async throws {
        try await withFixture(kind: .mp4) { source, package in
            _ = try await MediaProjectBridge.importSource(from: source, to: package)
            var document = try MediaProjectBridge.open(from: package)
            document.composition.overlays = [.init(
                kind: .callout,
                range: .init(start: .zero, duration: document.composition.duration),
                payload: "Legacy"
            )]
            let manifest = try MediaProjectBridge.save(document, to: package)
            var object = try #require(JSONSerialization.jsonObject(with: AeroProjectMigrator.encode(manifest)) as? [String: Any])
            object["schemaVersion"] = 1
            var composition = try #require(object["mediaComposition"] as? [String: Any])
            var overlays = try #require(composition["timedOverlays"] as? [[String: Any]])
            overlays[0].removeValue(forKey: "bounds")
            overlays[0].removeValue(forKey: "colorRGBA")
            composition["timedOverlays"] = overlays
            object["mediaComposition"] = composition
            try JSONSerialization.data(withJSONObject: object).write(
                to: package.appending(path: AeroProjectPackageStore.manifestFileName)
            )

            let reopened = try MediaProjectBridge.open(from: package)
            let overlay = try #require(reopened.composition.overlays.first)
            #expect(overlay.bounds == .legacyCallout)
            #expect(overlay.color == .legacyCallout)
            _ = try MediaProjectBridge.save(reopened, to: package)
            let savedData = try Data(contentsOf: package.appending(path: AeroProjectPackageStore.manifestFileName))
            let savedObject = try #require(JSONSerialization.jsonObject(with: savedData) as? [String: Any])
            #expect(savedObject["schemaVersion"] as? Int == 2)
            let savedComposition = try #require(savedObject["mediaComposition"] as? [String: Any])
            let savedOverlays = try #require(savedComposition["timedOverlays"] as? [[String: Any]])
            #expect(savedOverlays[0]["bounds"] != nil)
            #expect(savedOverlays[0]["colorRGBA"] != nil)
        }
    }

    private enum FixtureKind { case mp4, gif }

    private func withFixture(
        kind: FixtureKind,
        _ body: (URL, URL) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MediaBridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: kind == .mp4 ? "source.mp4" : "source.gif")
        switch kind { case .mp4: try makeMP4(at: source); case .gif: try makeGIF(at: source) }
        try await body(source, root.appending(path: "project.aeroshot"))
    }

    private func makeMP4(at url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240
        ])
        writer.add(input)
        guard writer.startWriting() else { throw FixtureError.failed }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 320, 240, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer, adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw FixtureError.failed
            }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw FixtureError.failed }
    }

    private func makeGIF(at url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil),
              let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { throw FixtureError.failed }
        let properties: CFDictionary = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.failed }
    }

    private func writeManifest(_ manifest: AeroProjectManifest, package: URL) throws {
        try AeroProjectMigrator.encode(manifest).write(to: package.appending(path: AeroProjectPackageStore.manifestFileName))
    }

    private func replacingDuration(in asset: AeroProjectAsset, with duration: AeroMediaTime?) -> AeroProjectAsset {
        var metadata = asset.metadata
        metadata.duration = duration
        return AeroProjectAsset(id: asset.id, relativePath: asset.relativePath, sha256: asset.sha256,
                                byteCount: asset.byteCount, isImmutableOriginal: asset.isImmutableOriginal, metadata: metadata)
    }

    private func t(_ value: Int64, _ scale: Int32 = 1) -> RationalTime { try! RationalTime(value, scale) }
    private func fixedID(_ suffix: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, suffix))
    }
    private enum FixtureError: Error { case failed }
}
