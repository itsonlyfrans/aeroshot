import AppKit
import AVFoundation
import Foundation
import ImageIO
import Testing

@testable import Aeroshot

@Suite(.serialized) @MainActor
struct PerformanceReleaseTests {
    @Test func performanceCountersTrackQueueStateAndFirstError() {
        let counters = PerformanceCounters()
        #expect(counters.reservePending(.video, limit: 2))
        #expect(counters.reservePending(.video, limit: 2))
        #expect(!counters.reservePending(.video, limit: 2))
        #expect(counters.reservePending(.systemAudio, limit: 1))
        #expect(!counters.reservePending(.systemAudio, limit: 1))
        #expect(counters.reservePending(.microphone, limit: 1))
        counters.recordArrival(.gif)
        counters.recordIncompleteSample()
        counters.recordPausedSample()
        counters.setScratchBytes(4_096)
        counters.recordCompletion(.video, appended: true)
        counters.recordCompletion(.video, appended: true)
        counters.recordCompletion(.systemAudio, appended: false, terminalError: "first failure")
        counters.recordCompletion(.microphone, appended: true, terminalError: "later failure")
        counters.recordCompletion(.gif, appended: true, terminalError: "later failure")

        #expect(counters.snapshot == PerformanceCounterSnapshot(
            arrivedSamples: 7,
            appendedSamples: 4,
            droppedSamples: 3,
            backpressureDroppedSamples: 2,
            incompleteSamples: 1,
            pausedSamples: 1,
            pendingVideoBuffers: 0,
            pendingSystemAudioBuffers: 0,
            pendingMicrophoneBuffers: 0,
            scratchBytes: 4_096,
            firstTerminalError: "first failure"
        ))
        counters.reset()
        #expect(counters.snapshot == PerformanceCounterSnapshot())
    }

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
        WP09Benchmark.emit(
            "package_round_trip",
            values: roundTrip,
            state: "warm",
            fixture: "synthetic-package",
            fixtureChecksum: asset.sha256
        )
        try Data("{truncated".utf8).write(to: root.appending(path: AeroProjectPackageStore.manifestFileName), options: .atomic)
        let recovery = try WP09Benchmark.samples(count: 20) { _ = try store.loadRecoveringIfNeeded() }
        WP09Benchmark.emit(
            "package_recovery",
            values: recovery,
            state: "warm",
            fixture: "synthetic-package",
            fixtureChecksum: asset.sha256
        )
    }

    @Test func annotationGeometryAndRenderBenchmark() throws {
        let annotations = ReleaseCorpus.makeAnnotations(count: 100)
        let geometry = WP09Benchmark.samples(count: 50) {
            for annotation in annotations { _ = AnnotationGeometry.bounds(for: annotation); _ = AnnotationGeometry.hitTest(.zero, annotation: annotation, tolerance: 6) }
        }
        WP09Benchmark.emit(
            "annotation_geometry_100",
            values: geometry,
            state: "warm",
            fixture: "synthetic-annotation-100",
            fixtureChecksum: "seed-\(ReleaseCorpus.seed)"
        )
        guard let context = CGContext(data: nil, width: 1_024, height: 768, bitsPerComponent: 8, bytesPerRow: 4_096,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { Issue.record("context"); return }
        let render = WP09Benchmark.samples(count: 30) { for annotation in annotations { AnnotationRenderer.draw(annotation, in: context) } }
        WP09Benchmark.emit(
            "annotation_render_100",
            values: render,
            state: "warm",
            fixture: "synthetic-annotation-100",
            fixtureChecksum: "seed-\(ReleaseCorpus.seed)"
        )
    }

    @Test func canvas100V1DeterministicSixtySecondReplay() throws {
        let first = try replayCanvas100V1(measureFrames: true)
        let second = try replayCanvas100V1(measureFrames: false)

        #expect(first.finalState == second.finalState)
        #expect(first.frameTimes.count == 3_600)
        #expect(first.finalState.annotationCount == 100)
        #expect(first.finalState.undoCount > 0)
        WP09Benchmark.emit(
            "canvas_100_v1_frame",
            values: first.frameTimes,
            state: "warm_deterministic_replay",
            fixture: "canvas-100-v1",
            fixtureChecksum: "seed-\(ReleaseCorpus.seed)"
        )
        print(
            "WP09_CANVAS fixture=canvas-100-v1 logicalSeconds=60 frames=\(first.frameTimes.count) " +
            "p95=\(WP09Benchmark.percentile(0.95, of: first.frameTimes)) " +
            "p99=\(WP09Benchmark.percentile(0.99, of: first.frameTimes)) " +
            "hitchesOver33_4ms=\(first.frameTimes.filter { $0 > 33.4 }.count)"
        )
    }

    @Test func longTimelineAlgebraBenchmark() throws {
        let model = try ReleaseCorpus.makeTimeline(sliceCount: 10_000)
        let values = WP09Benchmark.samples(count: 50) {
            #expect(model.validate().isEmpty)
            #expect(model.duration == (try? RationalTime(10_000, 30)))
        }
        WP09Benchmark.emit(
            "timeline_algebra_10000",
            values: values,
            state: "warm",
            fixture: "synthetic-timeline-10000",
            fixtureChecksum: "seed-\(ReleaseCorpus.seed)"
        )
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
        WP09Benchmark.emit(
            "gif_bounded_spool_append",
            values: values,
            state: "cold_io_then_warm",
            fixture: "gif-spool-srgb",
            fixtureChecksum: corpus.checksums.srgbPNG
        )

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
        let result = try await MediaExportCoordinator().export(snapshot: snapshot, preset: preset, destination: destination) { value in await progress.record(value) }
        let elapsed = ContinuousClock.now - start
        let first = try #require(await progress.firstDuration)
        let firstMS = WP09Benchmark.milliseconds(first)
        WP09Benchmark.emit(
            "export_first_progress",
            values: [firstMS],
            state: "cold",
            fixture: "synthetic-av",
            fixtureChecksum: corpus.checksums.mp4WithAudio
        )
        #expect(firstMS < 500)
        #expect(await progress.values.first == 0)
        #expect(await progress.values.last == 1)
        let elapsedMS = WP09Benchmark.milliseconds(elapsed)
        #expect(elapsedMS > 0)
        #expect(result.byteCount > 0)
        #expect(result.encoderEvidence == .verifiedOutputCodec(
            codec: .h264,
            hardwareUseObservable: false,
            fallbackObservable: false
        ))
        let bytesPerSecond = Double(result.byteCount) / (elapsedMS / 1_000)
        print(
            "WP09_EXPORT_THROUGHPUT bytes=\(result.byteCount) elapsedMS=\(elapsedMS) " +
            "bytesPerSecond=\(bytesPerSecond) outputValid=true codec=h264 " +
            "hardwareUseObservable=false fallbackObservable=false"
        )

        let cancelDestination = corpus.root.appending(path: "cancelled.mp4")
        let task = Task { try await MediaExportCoordinator().export(snapshot: snapshot, preset: preset, destination: cancelDestination) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch let error as MediaExportError { #expect(error == .cancelled) }
        #expect(!FileManager.default.fileExists(atPath: cancelDestination.path))
    }

    private func replayCanvas100V1(measureFrames: Bool) throws -> CanvasReplayResult {
        let size = CGSize(width: 1_024, height: 768)
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw CanvasReplayError.context
        }
        let document = EditorDocument(image: image)
        document.annotations = ReleaseCorpus.makeAnnotations(count: 100)
        var frameTimes: [Double] = []
        if measureFrames { frameTimes.reserveCapacity(3_600) }

        for frame in 0..<3_600 {
            let start = ContinuousClock.now
            let phase = CGFloat(frame % 300) / 300
            document.zoomScale = 0.75 + phase * 1.25
            document.panOffset = CGPoint(x: CGFloat((frame * 7) % 161) - 80, y: CGFloat((frame * 11) % 121) - 60)

            if frame.isMultiple(of: 60) {
                document.selectOnly(document.annotations[(frame / 60) % document.annotations.count].id)
            }
            if frame.isMultiple(of: 90) {
                let x = CGFloat((frame * 13) % 800)
                document.selection = AnnotationSelectionController.marqueeSelection(
                    in: CGRect(x: x, y: CGFloat((frame * 17) % 520), width: 160, height: 120),
                    annotations: document.annotations
                )
            }
            if frame.isMultiple(of: 120), !document.selectedAnnotations.isEmpty {
                let delta = CGPoint(x: frame.isMultiple(of: 240) ? 3 : -3, y: frame.isMultiple(of: 360) ? 2 : -2)
                let moved = AnnotationSelectionController.moved(document.selectedAnnotations, by: delta, within: size)
                _ = document.replaceSelected(with: moved, name: "Canvas replay drag")
            }
            if frame.isMultiple(of: 180), let original = document.selectedAnnotations.first(where: { $0.points.count >= 2 }) {
                let point = CGPoint(x: original.points.last!.x + 4, y: original.points.last!.y + 3)
                let resized = AnnotationSelectionController.resized(original, handleIndex: 1, to: point, within: size)
                _ = document.transformAnnotation(id: original.id, to: resized)
            }
            if frame.isMultiple(of: 240), !document.selectedAnnotations.isEmpty {
                let width = Double(1 + (frame / 240) % 16)
                _ = AnnotationInspectorController(document: document).update(.strokeWidth, value: width)
            }

            context.clear(CGRect(origin: .zero, size: size))
            context.saveGState()
            context.translateBy(x: document.panOffset.x, y: document.panOffset.y)
            context.scaleBy(x: document.zoomScale, y: document.zoomScale)
            for annotation in document.annotations {
                AnnotationRenderer.draw(annotation, in: context)
            }
            context.restoreGState()
            if measureFrames { frameTimes.append(WP09Benchmark.milliseconds(ContinuousClock.now - start)) }
        }

        let first = try #require(document.annotations.first)
        let last = try #require(document.annotations.last)
        return CanvasReplayResult(
            frameTimes: frameTimes,
            finalState: CanvasReplayState(
                annotationCount: document.annotations.count,
                firstPoints: first.points,
                lastPoints: last.points,
                selectedIDs: document.selection.orderedIDs,
                primaryID: document.selection.primaryID,
                zoomScale: document.zoomScale,
                panOffset: document.panOffset,
                undoCount: document.undoStack.undoCommands.count
            )
        )
    }
}

private actor ProgressProbe {
    let start = ContinuousClock.now
    private(set) var values: [Double] = []
    private(set) var firstDuration: Duration?
    func record(_ value: Double) { if firstDuration == nil { firstDuration = ContinuousClock.now - start }; values.append(value) }
}

private struct CanvasReplayResult {
    let frameTimes: [Double]
    let finalState: CanvasReplayState
}

private struct CanvasReplayState: Equatable {
    let annotationCount: Int
    let firstPoints: [CGPoint]
    let lastPoints: [CGPoint]
    let selectedIDs: [UUID]
    let primaryID: UUID?
    let zoomScale: CGFloat
    let panOffset: CGPoint
    let undoCount: Int
}

private enum CanvasReplayError: Error { case context }
