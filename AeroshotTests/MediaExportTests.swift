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
    private enum FixtureError: Error { case writerSetup }
}
