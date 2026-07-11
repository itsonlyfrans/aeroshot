import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import Aeroshot

struct MediaExportTests {
    @Test func snapshotIsImmutableAndOverlayOrderIsDeterministic() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let asset = fixtureAsset(relativePath: "assets/source.mp4")
        var manifest = AeroProjectManifest(
            id: fixedID(1), assets: [asset], primarySourceAssetID: asset.id,
            overlays: [overlay(id: fixedID(3), z: 2), overlay(id: fixedID(2), z: 1)]
        )
        let snapshot = try MediaExportSnapshot(manifest: manifest, packageURL: root)
        manifest.overlays.removeAll()

        #expect(snapshot.overlays.map(\.id) == [fixedID(2), fixedID(3)])
        #expect(MediaOverlayCompiler.compile(snapshot).map(\.id) == [fixedID(2), fixedID(3)])
        #expect(snapshot.effectiveSourceRange == nil)
    }

    @Test func timedTextContentSurvivesOfflineRenderContract() {
        let asset = fixtureAsset(relativePath: "source.mp4")
        let timed = AeroOverlay(id: fixedID(4), kind: .text,
            geometry: .init(bounds: .init(x: 0.1, y: 0.1, width: 0.4, height: 0.1), points: []),
            appearance: .init(strokeRGBA: [1, 1, 1, 1], fillRGBA: [0, 0, 0, 0.8], strokeWidth: 1, opacity: 1),
            transform: .init(rotationRadians: 0, scaleX: 1, scaleY: 1), zIndex: 0,
            timeRange: nil, content: "Watch this")
        let snapshot = MediaExportSnapshot(projectID: fixedID(1), sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            sourceAsset: asset, canvas: .source, overlays: [timed])
        #expect(MediaOverlayCompiler.compile(snapshot).first?.content == "Watch this")
    }

    @Test func presetsValidateAndEstimateDeterministically() throws {
        let fps = try AeroMediaTime(value: 30_000, timescale: 1_001)
        let preset = MediaExportPreset.h264(size: try AeroPixelSize(width: 1_920, height: 1_080), frameRate: fps)
        try preset.validate()
        let first = preset.estimatedSize(durationSeconds: 60)
        #expect(first == preset.estimatedSize(durationSeconds: 60))
        #expect(first.bytes > 0)
        #expect(first.uncertaintyFraction == 0.25)

        let odd = MediaExportPreset.h264(size: try AeroPixelSize(width: 1_919, height: 1_080), frameRate: fps)
        #expect(throws: MediaExportError.invalidResolution) { try odd.validate() }
    }

    @Test func generatedFixtureExportsAtomicallyAndReportsTruth() async throws {
        try await withFixture { source, directory in
            let destination = directory.appending(path: "result.mp4")
            try Data("old destination".utf8).write(to: destination)
            let coordinator = MediaExportCoordinator()
            let result = try await coordinator.export(
                snapshot: snapshot(source), preset: try preset(), destination: destination
            )
            let output = AVURLAsset(url: destination)
            let duration = try await output.load(.duration)
            let tracks = try await output.loadTracks(withMediaType: .video)
            #expect(duration.seconds > 0)
            #expect(!tracks.isEmpty)
            #expect(result.byteCount > 0)
            #expect(result.encoderEvidence == .verifiedOutputCodec(
                codec: .h264,
                hardwareUseObservable: false,
                fallbackObservable: false
            ))
            #expect(partials(in: directory).isEmpty)
        }
    }

    @Test @MainActor func offlineExportBurnsTimedShapeAndCalloutIntoPixels() async throws {
        try await withFixture { source, directory in
            let asset = fixtureAsset(relativePath: source.lastPathComponent)
            let sourceID = fixedID(9)
            let model = MediaCompositionModel(
                assets: [MediaSourceAsset(id: sourceID, url: source, duration: try RationalTime(2), hasVideo: true, hasAudio: false)],
                slices: [MediaSlice(sourceAssetID: sourceID, sourceRange: try RationalTimeRange(start: .zero, duration: RationalTime(2)))]
            )
            let compiled = try await MediaCompositionCompiler().compile(model)
            let flattened = directory.appending(path: "flattened.mp4")
            let flattenSession = try #require(AVAssetExportSession(asset: compiled.composition, presetName: AVAssetExportPresetHighestQuality))
            try await flattenSession.export(to: flattened, as: .mp4)
            let timedOverlay = AeroOverlay(id: fixedID(42), kind: .shape,
                geometry: .init(bounds: .init(x: 0.7, y: 0.7, width: 0.2, height: 0.2), points: []),
                appearance: .init(strokeRGBA: [0, 1, 0, 1], fillRGBA: [0, 1, 0, 1], strokeWidth: 0, opacity: 1),
                transform: .init(rotationRadians: 0, scaleX: 1, scaleY: 1), zIndex: 0,
                timeRange: try AeroMediaTimeRange(start: .zero, duration: AeroMediaTime(value: 1, timescale: 1)))
            let textOverlay = AeroOverlay(id: fixedID(43), kind: .text,
                geometry: .init(bounds: .init(x: 0.3, y: 0.4, width: 0.4, height: 0.2), points: []),
                appearance: .init(strokeRGBA: [0, 0.8, 1, 1], fillRGBA: [0.08, 0.08, 0.08, 0.88], strokeWidth: 2, opacity: 1),
                transform: .init(rotationRadians: 0, scaleX: 1, scaleY: 1), zIndex: 1,
                timeRange: try AeroMediaTimeRange(start: .zero, duration: AeroMediaTime(value: 1, timescale: 1)),
                content: "Callout")
            let snapshot = MediaExportSnapshot(projectID: fixedID(1), sourceURL: flattened, sourceAsset: asset,
                canvas: .source, overlays: [timedOverlay, textOverlay])
            let destination = directory.appending(path: "overlays.mp4")
            let largePreset = MediaExportPreset.h264(size: try AeroPixelSize(width: 1_728, height: 1_080),
                frameRate: try AeroMediaTime(value: 120, timescale: 1))
            _ = try await MediaExportCoordinator().export(snapshot: snapshot, preset: largePreset, destination: destination)
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: destination))
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let image = try await generator.image(at: CMTime(value: 3, timescale: 30)).image

            let timedPixel = try #require(pixel(image, x: 1_382, y: 864))
            #expect(timedPixel.g > 200 && timedPixel.r < 40 && timedPixel.b < 40)
            #expect(containsPixel(image, x: 540..<1_188, y: 450..<630) { $0.b > 180 && $0.g > 120 && $0.r < 60 })
        }
    }

    @Test func cancellationLeavesDestinationAndNoPartialFile() async throws {
        try await withFixture(frameCount: 600) { source, directory in
            let destination = directory.appending(path: "existing.mp4")
            let sentinel = Data("keep me".utf8)
            try sentinel.write(to: destination)
            let coordinator = MediaExportCoordinator()
            let task = Task {
                try await coordinator.export(snapshot: snapshot(source), preset: try preset(), destination: destination)
            }
            task.cancel()
            do {
                _ = try await task.value
                Issue.record("Expected cancellation")
            } catch let error as MediaExportError {
                #expect(error == .cancelled)
            }
            #expect(try Data(contentsOf: destination) == sentinel)
            #expect(partials(in: directory).isEmpty)
        }
    }

    @Test func retinaAndUltrawideCropEffectExportsMatchRequestedCanvas() async throws {
        try await withFixture { source, directory in
            let asset = fixtureAsset(relativePath: source.lastPathComponent)
            let effect = AeroOverlay(id: fixedID(88), kind: .shape,
                geometry: .init(bounds: .init(x: 0.45, y: 0.45, width: 0.1, height: 0.1), points: []),
                appearance: .init(strokeRGBA: [1, 0.5, 0, 1], fillRGBA: nil, strokeWidth: 5, opacity: 1),
                transform: .init(rotationRadians: 0, scaleX: 1, scaleY: 1), zIndex: 0, content: "effect.click")
            for (name, size) in [("retina", try AeroPixelSize(width: 1_280, height: 720)),
                                 ("ultrawide", try AeroPixelSize(width: 2_560, height: 1_080))] {
                let destination = directory.appending(path: "\(name).mp4")
                let canvas = AeroProjectCanvas(crop: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                    background: .source, backgroundColorRGBA: nil, aspectRatio: nil, colorSpacePolicy: .preserveSource)
                let snapshot = MediaExportSnapshot(projectID: fixedID(1), sourceURL: source, sourceAsset: asset,
                    canvas: canvas, overlays: [effect])
                _ = try await MediaExportCoordinator().export(snapshot: snapshot,
                    preset: .h264(size: size, frameRate: try AeroMediaTime(value: 30, timescale: 1)), destination: destination)
                let track = try #require(try await AVURLAsset(url: destination).loadTracks(withMediaType: .video).first)
                let natural = try await track.load(.naturalSize)
                #expect(Int(abs(natural.width)) == size.width)
                #expect(Int(abs(natural.height)) == size.height)
                let frame = try await AVAssetImageGenerator(asset: AVURLAsset(url: destination)).image(at: .zero).image
                #expect(frame.width == size.width)
                #expect(frame.height == size.height)
            }
        }
    }

    private func withFixture(
        frameCount: Int = 60,
        _ body: (URL, URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AeroshotMediaExport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "fixture.mp4")
        try makeFixture(at: source, frameCount: frameCount)
        try await body(source, directory)
    }

    private func makeFixture(at url: URL, frameCount: Int) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 500_000]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320,
            kCVPixelBufferHeightKey as String: 240
        ])
        guard writer.canAdd(input) else { throw FixtureError.writerSetup }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError.writerSetup }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 320, 240, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { throw FixtureError.writerSetup }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(index % 255), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else {
                throw writer.error ?? FixtureError.writerSetup
            }
        }
        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.writerSetup }
    }

    private func snapshot(_ url: URL) -> MediaExportSnapshot {
        MediaExportSnapshot(projectID: fixedID(1), sourceURL: url, sourceAsset: fixtureAsset(relativePath: url.lastPathComponent), canvas: .source)
    }

    @Test func partialURLsAreHiddenSiblingsAndUniquePerExport() {
        let destination = URL(fileURLWithPath: "/tmp/exports/demo.mp4")
        let first = MediaExportCoordinator.partialURL(for: destination)
        let second = MediaExportCoordinator.partialURL(for: destination)

        #expect(first != second)
        for partial in [first, second] {
            #expect(partial.deletingLastPathComponent().path == destination.deletingLastPathComponent().path)
            #expect(partial.lastPathComponent.hasPrefix(".demo.mp4."))
            #expect(partial.lastPathComponent.hasSuffix(".partial.mp4"))
        }
    }

    private func preset() throws -> MediaExportPreset {
        .h264(size: try AeroPixelSize(width: 320, height: 240), frameRate: try AeroMediaTime(value: 30, timescale: 1))
    }

    private func fixtureAsset(relativePath: String) -> AeroProjectAsset {
        AeroProjectAsset(id: fixedID(9), relativePath: relativePath, sha256: "fixture", byteCount: 1, isImmutableOriginal: true,
                         metadata: AeroMediaMetadata(mediaType: .video, pixelSize: try! AeroPixelSize(width: 320, height: 240),
                                                    duration: try! AeroMediaTime(value: 2, timescale: 1),
                                                    nominalFrameRate: try! AeroMediaTime(value: 30, timescale: 1),
                                                    colorSpaceName: "ITU_R_709_2", hasAudio: false))
    }

    private func overlay(id: UUID, z: Int) -> AeroOverlay {
        AeroOverlay(id: id, kind: .shape,
                    geometry: .init(bounds: .init(x: 0, y: 0, width: 1, height: 1), points: []),
                    appearance: .init(strokeRGBA: [1, 0, 0, 1], fillRGBA: nil, strokeWidth: 2, opacity: 1),
                    transform: .init(rotationRadians: 0, scaleX: 1, scaleY: 1), zIndex: z)
    }

    private func fixedID(_ value: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))! }
    private func partials(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?.filter { $0.lastPathComponent.contains(".partial.mp4") } ?? []
    }
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
              x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        let offset = y * image.bytesPerRow + x * 4
        return (bytes[offset + 2], bytes[offset + 1], bytes[offset])
    }
    private func containsPixel(_ image: CGImage, x: Range<Int>, y: Range<Int>,
                               matching predicate: ((r: UInt8, g: UInt8, b: UInt8)) -> Bool) -> Bool {
        for row in y { for column in x { if let value = pixel(image, x: column, y: row), predicate(value) { return true } } }
        return false
    }
    private enum FixtureError: Error { case writerSetup }
}
