import AppKit
import AVFoundation
import Foundation
import ImageIO
import Testing

@testable import Aeroshot

@Suite(.serialized) @MainActor
struct PerformanceReleaseTests {
    @Test func deterministicGoldenCorpusAndMetadata() async throws {
        let first = try ReleaseCorpus.build(); defer { ReleaseCorpus.remove(first) }
        let second = try ReleaseCorpus.build(); defer { ReleaseCorpus.remove(second) }
        // ImageIO output and malformed byte fixtures are byte-stable. AVAssetWriter
        // embeds container metadata, so the MP4 is checked semantically below and
        // its per-run checksum is evidence, not falsely asserted as byte-stable.
        #expect(first.checksums.srgbPNG == second.checksums.srgbPNG)
        #expect(first.checksums.displayP3PNG == second.checksums.displayP3PNG)
        #expect(first.checksums.scrollingPNG == second.checksums.scrollingPNG)
        #expect(first.checksums.timedGIF == second.checksums.timedGIF)
        #expect(first.checksums.corruptAsset == second.checksums.corruptAsset)
        #expect(first.checksums.truncatedAsset == second.checksums.truncatedAsset)
        #expect(first.annotations.count == 100)
        #expect(first.timeline.slices.count == 10_000)
        #expect(first.timeline.validate().isEmpty)

        let video = AVURLAsset(url: first.mp4WithAudio)
        #expect(try await video.loadTracks(withMediaType: .video).count == 1)
        #expect(try await video.loadTracks(withMediaType: .audio).count == 1)
        let gif = try #require(CGImageSourceCreateWithURL(first.timedGIF as CFURL, nil))
        #expect(CGImageSourceGetCount(gif) == 3)
        let properties = try #require(CGImageSourceCopyProperties(gif, nil) as? [CFString: Any])
        let gifProperties = try #require(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        #expect(gifProperties[kCGImagePropertyGIFLoopCount] as? Int == 4)
        #expect(CGImageSourceCreateWithURL(first.corruptAsset as CFURL, nil) == nil || CGImageSourceGetStatus(CGImageSourceCreateWithURL(first.corruptAsset as CFURL, nil)!) != .statusComplete)
        let truncated = try #require(CGImageSourceCreateWithURL(first.truncatedAsset as CFURL, nil))
        #expect(CGImageSourceGetStatus(truncated) != .statusComplete)
        print("WP09_CORPUS seed=\(ReleaseCorpus.seed) checksums=\(String(data: try JSONEncoder().encode(first.checksums), encoding: .utf8)!)")
    }

    @Test func packageRoundTripAndRecoveryBenchmark() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Aeroshot-WP09-Package-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AeroProjectPackageStore(packageURL: root, now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let data = Data((0..<65_536).map { UInt8(($0 * 31) & 0xff) })
        let asset = try store.storeOriginal(data, id: ReleaseCorpus.fixedID(1), fileExtension: "bin",
            metadata: AeroMediaMetadata(mediaType: .auxiliary, pixelSize: nil, duration: nil, nominalFrameRate: nil, colorSpaceName: nil, hasAudio: false))
        var manifest = AeroProjectManifest(id: ReleaseCorpus.fixedID(2), createdAt: Date(timeIntervalSince1970: 1_700_000_000), assets: [asset], primarySourceAssetID: asset.id)
        _ = try store.save(manifest)
        manifest.canvas = AeroProjectCanvas(crop: AeroNormalizedRect(x: 0, y: 0, width: 1, height: 1), background: .transparent, colorSpacePolicy: .preserveSource)
        _ = try store.save(manifest)
        let roundTrip = try WP09Benchmark.samples(count: 20) {
            let first = try store.load()
            let second = try store.load()
            #expect(first == second)
        }
        WP09Benchmark.emit("package_round_trip", values: roundTrip, state: "warm")
        try Data("{truncated".utf8).write(to: root.appending(path: AeroProjectPackageStore.manifestFileName), options: .atomic)
        let recovery = try WP09Benchmark.samples(count: 20) { _ = try store.loadRecoveringIfNeeded() }
        WP09Benchmark.emit("package_recovery", values: recovery, state: "warm")
    }

    @Test func annotationGeometryAndRenderBenchmark() throws {
        let annotations = ReleaseCorpus.makeAnnotations(count: 100)
        let geometry = WP09Benchmark.samples(count: 50) {
            for annotation in annotations { _ = AnnotationGeometry.bounds(for: annotation); _ = AnnotationGeometry.hitTest(.zero, annotation: annotation, tolerance: 6) }
        }
        WP09Benchmark.emit("annotation_geometry_100", values: geometry, state: "warm")
        guard let context = CGContext(data: nil, width: 1_024, height: 768, bitsPerComponent: 8, bytesPerRow: 4_096,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { Issue.record("context"); return }
        let render = WP09Benchmark.samples(count: 30) { for annotation in annotations { AnnotationRenderer.draw(annotation, in: context) } }
        WP09Benchmark.emit("annotation_render_100", values: render, state: "warm")
    }

    @Test func longTimelineAlgebraBenchmark() throws {
        let model = try ReleaseCorpus.makeTimeline(sliceCount: 10_000)
        let values = WP09Benchmark.samples(count: 50) {
            #expect(model.validate().isEmpty)
            #expect(model.duration == (try? RationalTime(10_000, 30)))
        }
        WP09Benchmark.emit("timeline_algebra_10000", values: values, state: "warm")
    }

    @Test func gifSpoolAndCacheBoundsBenchmark() throws {
        let corpus = try ReleaseCorpus.build(); defer { ReleaseCorpus.remove(corpus) }
        let source = try #require(CGImageSourceCreateWithURL(corpus.srgbPNG as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let spoolDirectory = corpus.root.appending(path: "spool")
        let spool = try GIFFrameSpool(directoryURL: spoolDirectory, limits: .init(maximumFrameCount: 12, maximumBytes: 10_000_000))
        let values = try WP09Benchmark.samples(count: 20) { _ = try spool.append(image, durationMicroseconds: 50_000) }
        #expect(spool.statistics.frameCount == 12)
        #expect(spool.statistics.byteCount <= 10_000_000)
        #expect(spool.statistics.residentDecodedFrameCount == 0)
        WP09Benchmark.emit("gif_bounded_spool_append", values: values, state: "cold_io_then_warm")

        let frames = try (0..<20).map { try GIFFrame(id: ReleaseCorpus.fixedID(20_000 + $0), sourceURL: corpus.srgbPNG, durationMicroseconds: 50_000) }
        let document = try GIFDocument(frames: frames)
        let studio = GIFStudioDocument(document: document, projectAdapter: GIFStudioProjectAdapter { _ in })
        #expect(studio.residentDecodedPreviewCount <= GIFStudioDocument.previewCacheCountLimit)
        #expect(GIFStudioDocument.previewCacheCountLimit == 6)
    }

    @Test func colorMetadataPreservationWhereExposed() throws {
        let corpus = try ReleaseCorpus.build(); defer { ReleaseCorpus.remove(corpus) }
        for (url, expectedName) in [(corpus.srgbPNG, "sRGB"), (corpus.displayP3PNG, "Display P3")] {
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let name = image.colorSpace?.name as String?
            let normalizedName = name?.lowercased().filter(\.isLetter)
            let normalizedExpected = expectedName.lowercased().filter(\.isLetter)
            #expect(normalizedName?.contains(normalizedExpected) == true, "actual color space: \(name ?? "nil")")
        }
    }

    @Test func exportProgressAndCancellationAreObservable() async throws {
        let corpus = try ReleaseCorpus.build(); defer { ReleaseCorpus.remove(corpus) }
        let destination = corpus.root.appending(path: "export.mp4")
        let asset = AeroProjectAsset(id: ReleaseCorpus.fixedID(70), relativePath: corpus.mp4WithAudio.lastPathComponent,
            sha256: try ReleaseCorpus.checksum(corpus.mp4WithAudio), byteCount: Int64((try Data(contentsOf: corpus.mp4WithAudio)).count), isImmutableOriginal: true,
            metadata: AeroMediaMetadata(mediaType: .video, pixelSize: try AeroPixelSize(width: 160, height: 120), duration: try AeroMediaTime(value: 12, timescale: 30), nominalFrameRate: try AeroMediaTime(value: 30, timescale: 1), colorSpaceName: "ITU_R_709_2", hasAudio: true))
        let snapshot = MediaExportSnapshot(projectID: ReleaseCorpus.fixedID(71), sourceURL: corpus.mp4WithAudio, sourceAsset: asset, canvas: .source)
        let preset = MediaExportPreset.h264(size: try AeroPixelSize(width: 160, height: 120), frameRate: try AeroMediaTime(value: 30, timescale: 1))
        let start = ContinuousClock.now
        let progress = ProgressProbe()
        _ = try await MediaExportCoordinator().export(snapshot: snapshot, preset: preset, destination: destination) { value in await progress.record(value) }
        let first = try #require(await progress.firstDuration)
        let firstMS = WP09Benchmark.milliseconds(first)
        print("WP09_METRIC name=export_first_progress unit=ms n=1 state=cold raw=[\(String(format: "%.3f", firstMS))]")
        #expect(firstMS < 500)
        #expect(await progress.values.first == 0)
        #expect(await progress.values.last == 1)
        #expect(WP09Benchmark.milliseconds(ContinuousClock.now - start) > 0)

        let cancelDestination = corpus.root.appending(path: "cancelled.mp4")
        let task = Task { try await MediaExportCoordinator().export(snapshot: snapshot, preset: preset, destination: cancelDestination) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch let error as MediaExportError { #expect(error == .cancelled) }
        #expect(!FileManager.default.fileExists(atPath: cancelDestination.path))
    }
}

private actor ProgressProbe {
    let start = ContinuousClock.now
    private(set) var values: [Double] = []
    private(set) var firstDuration: Duration?
    func record(_ value: Double) { if firstDuration == nil { firstDuration = ContinuousClock.now - start }; values.append(value) }
}
