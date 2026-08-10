import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import Aeroshot

struct MediaExportTests {
    @Test func cropLayoutLocksFitPlacementAndPointMapping() throws {
        let source = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)

        let uncropped = try #require(MediaCropLayout.make(
            sourceRect: source,
            outputRect: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
            normalizedCrop: CGRect(x: 0, y: 0, width: 1, height: 1)
        ))
        #expect(abs(uncropped.transformedSourceRect.minX) < 0.000_001)
        #expect(abs(uncropped.transformedSourceRect.minY - 218.75) < 0.000_001)
        #expect(abs(uncropped.transformedSourceRect.width - 1_000) < 0.000_001)
        #expect(abs(uncropped.transformedSourceRect.height - 562.5) < 0.000_001)

        let centered = try #require(MediaCropLayout.make(
            sourceRect: source,
            outputRect: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
            normalizedCrop: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        ))
        #expect(centered.cropRect == CGRect(x: 480, y: 270, width: 960, height: 540))
        #expect(abs(centered.fittedCropRect.minY - 218.75) < 0.000_001)
        #expect(abs(centered.transformedSourceRect.minX + 500) < 0.000_001)
        #expect(abs(centered.transformedSourceRect.minY + 62.5) < 0.000_001)
        #expect(centered.outputPoint(forSourceNormalized: CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 500, y: 500))
        #expect(centered.outputPoint(forSourceNormalized: CGPoint(x: 0.1, y: 0.5)) == nil)

        let offCenter = try #require(MediaCropLayout.make(
            sourceRect: source,
            outputRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            normalizedCrop: CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.6)
        ))
        #expect(abs(offCenter.fittedCropRect.minX - 44.444_444_444_4) < 0.000_001)
        #expect(abs(offCenter.fittedCropRect.minY) < 0.000_001)
        let mapped = try #require(offCenter.outputPoint(forSourceNormalized: CGPoint(x: 0.3, y: 0.5)))
        #expect(abs(mapped.x - 400) < 0.000_001)
        #expect(abs(mapped.y - 300) < 0.000_001)

        // Preferred transforms can produce standardized source bounds with a nonzero origin.
        // These values lock the original export equation: fit offset - absolute crop origin × scale.
        let transformedOrigin = try #require(MediaCropLayout.make(
            sourceRect: CGRect(x: -1_080, y: 0, width: 1_080, height: 1_920),
            outputRect: CGRect(x: 0, y: 0, width: 540, height: 960),
            normalizedCrop: CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8)
        ))
        #expect(abs(transformedOrigin.scale - 0.625) < 0.000_001)
        #expect(abs(transformedOrigin.sourceTranslation.x - 607.5) < 0.000_001)
        #expect(abs(transformedOrigin.sourceTranslation.y + 120) < 0.000_001)
        #expect(abs(transformedOrigin.transformedSourceRect.minX + 67.5) < 0.000_001)
        #expect(abs(transformedOrigin.transformedSourceRect.minY + 120) < 0.000_001)
        let rotated = try #require(MediaSourceGeometry.orientedRect(
            naturalSize: CGSize(width: 1_920, height: 1_080),
            preferredTransform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1_080, ty: 0)
        ))
        #expect(rotated == CGRect(x: 0, y: 0, width: 1_080, height: 1_920))
        #expect(MediaCropLayout.make(sourceRect: .zero, outputRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                                     normalizedCrop: CGRect(x: 0, y: 0, width: 1, height: 1)) == nil)
    }

    @Test func cropLayoutRejectsDerivedTranslationOverflow() {
        let hugeOrigin = CGFloat.greatestFiniteMagnitude / 2
        #expect(MediaCropLayout.make(
            sourceRect: CGRect(x: hugeOrigin, y: 0, width: 1, height: 1),
            outputRect: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            normalizedCrop: CGRect(x: 0.5, y: 0, width: 1e-300, height: 1)
        ) == nil)
    }

    @Test func offCenterCropPixelsAreOrientedAndLetterboxIsMasked() async throws {
        try await withFixture { source, directory in
            let asset = fixtureAsset(relativePath: source.lastPathComponent)
            let outputSize = try AeroPixelSize(width: 320, height: 240)
            let frameRate = try AeroMediaTime(value: 30, timescale: 1)

            let topRight = MediaExportSnapshot(projectID: fixedID(1), sourceURL: source, sourceAsset: asset,
                canvas: .init(crop: .init(x: 0.5, y: 0, width: 0.5, height: 0.5), background: .source,
                              backgroundColorRGBA: nil, aspectRatio: nil, colorSpacePolicy: .preserveSource))
            let topRightURL = directory.appending(path: "top-right.mp4")
            _ = try await MediaExportCoordinator().export(snapshot: topRight,
                preset: .h264(size: outputSize, frameRate: frameRate), destination: topRightURL)
            let topRightImage = try await AVAssetImageGenerator(asset: AVURLAsset(url: topRightURL))
                .image(at: CMTime(value: 3, timescale: 30)).image
            let green = try #require(pixel(topRightImage, x: 160, y: 120))
            #expect(green.g > 180 && green.r < 60 && green.b < 60)

            let rightHalf = MediaExportSnapshot(projectID: fixedID(1), sourceURL: source, sourceAsset: asset,
                canvas: .init(crop: .init(x: 0.5, y: 0, width: 0.5, height: 1), background: .source,
                              backgroundColorRGBA: nil, aspectRatio: nil, colorSpacePolicy: .preserveSource))
            let rightHalfURL = directory.appending(path: "right-half.mp4")
            _ = try await MediaExportCoordinator().export(snapshot: rightHalf,
                preset: .h264(size: outputSize, frameRate: frameRate), destination: rightHalfURL)
            let rightHalfImage = try await AVAssetImageGenerator(asset: AVURLAsset(url: rightHalfURL))
                .image(at: CMTime(value: 3, timescale: 30)).image
            let bar = try #require(pixel(rightHalfImage, x: 20, y: 120))
            let visible = try #require(pixel(rightHalfImage, x: 160, y: 60))
            #expect(bar.r < 20 && bar.g < 20 && bar.b < 20)
            #expect(visible.g > 180 && visible.r < 60 && visible.b < 60)
        }
    }

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

    @Test func freezeTimingKeepsTimedVisualsAndClickAudioOnOneOutputTimeline() throws {
        let asset = fixtureAsset(relativePath: "source.mp4")
        let freeze = FreezeFrameEffect(timeMicroseconds: 1_000_000, durationMicroseconds: 1_000_000)
        let start = try AeroMediaTime(value: 800_000, timescale: 1_000_000)
        let duration = try AeroMediaTime(value: 500_000, timescale: 1_000_000)
        let visual = AeroOverlay(id: fixedID(4), kind: .shape,
            geometry: .init(bounds: .init(x: 0, y: 0, width: 1, height: 1), points: []),
            appearance: .init(strokeRGBA: [1, 1, 1, 1], fillRGBA: nil, strokeWidth: 1, opacity: 1),
            transform: .init(rotationRadians: 0, scaleX: 1, scaleY: 1), zIndex: 0,
            timeRange: try .init(start: start, duration: duration), content: "effect.click")
        let snapshot = MediaExportSnapshot(projectID: fixedID(1), sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            sourceAsset: asset, canvas: .source, overlays: [visual],
            effects: .init(events: [.init(kind: .click, timeMicroseconds: 1_200_000, x: 0.5, y: 0.5)], freezeFrame: freeze))

        let timing = MediaOutputTiming(freezeFrame: freeze)
        let outputVisual = try #require(MediaOverlayCompiler.compile(snapshot).first?.timeRange)
        #expect(timing.outputTimeMicroseconds(forSourceTime: 1_200_000) == 2_200_000)
        #expect(Double(outputVisual.start.value) / Double(outputVisual.start.timescale) == 0.8)
        #expect(Double(outputVisual.duration.value) / Double(outputVisual.duration.timescale) == 1.5)
    }

    @Test func freezeAddsItsFullRequestedDurationAndKeepsClickAudio() async throws {
        try await withFixture { source, directory in
            let asset = fixtureAsset(relativePath: source.lastPathComponent)
            let effects = PresentationEffectsState(
                events: [.init(kind: .click, timeMicroseconds: 1_000_000, x: 0.5, y: 0.5)],
                freezeFrame: .init(timeMicroseconds: 1_000_000, durationMicroseconds: 1_000_000),
                punchInClickTimes: [1_000_000], clickSound: "snug_click"
            )
            let snapshot = MediaExportSnapshot(projectID: fixedID(1), sourceURL: source, sourceAsset: asset,
                                               canvas: .source, effects: effects)
            let destination = directory.appending(path: "effects.mp4")
            _ = try await MediaExportCoordinator().export(snapshot: snapshot, preset: try preset(), destination: destination)
            let input = AVURLAsset(url: source)
            let output = AVURLAsset(url: destination)
            let inputDuration = try await input.load(.duration)
            let duration = try await output.load(.duration)
            let audioTracks = try await output.loadTracks(withMediaType: .audio)
            #expect(CMTimeCompare(duration, CMTimeAdd(inputDuration, CMTime(seconds: 1, preferredTimescale: 600))) == 0)
            #expect(!audioTracks.isEmpty)
        }
    }

    @Test func freezeAcceptsEverySourceBoundaryAndRejectsInvalidTimes() async throws {
        try await withFixture { source, _ in
            let asset = AVURLAsset(url: source)
            let sourceDuration = try await asset.load(.duration)
            let hold = CMTime(seconds: 1, preferredTimescale: 600)
            for time: Int64 in [0, 1_000_000, 1_966_666, 2_000_000] {
                let frozen = try await MediaExportCoordinator.applyingFreeze(
                    to: asset,
                    freezeFrame: .init(timeMicroseconds: time, durationMicroseconds: 1_000_000)
                )
                let frozenDuration = try await frozen.load(.duration)
                #expect(CMTimeCompare(frozenDuration, CMTimeAdd(sourceDuration, hold)) == 0)
            }
            await #expect(throws: MediaExportError.invalidFreezeFrame) {
                _ = try await MediaExportCoordinator.applyingFreeze(
                    to: asset,
                    freezeFrame: .init(timeMicroseconds: -1, durationMicroseconds: 1_000_000)
                )
            }
            await #expect(throws: MediaExportError.invalidFreezeFrame) {
                _ = try await MediaExportCoordinator.applyingFreeze(
                    to: asset,
                    freezeFrame: .init(timeMicroseconds: 2_000_001, durationMicroseconds: 1_000_000)
                )
            }
        }
    }

    @Test @MainActor func frozenPreviewKeepsTheCompiledAudioMix() async throws {
        let corpus = try ReleaseCorpus.build()
        defer { ReleaseCorpus.remove(corpus) }
        let document = try await VideoStudioDocument.create(
            from: corpus.mp4WithAudio,
            packageURL: corpus.root.appending(path: "preview.aeroshot")
        )
        document.addFreezeFrame(at: .zero, duration: 0.1)

        var previewMix: AVAudioMix?
        for _ in 0..<120 {
            if let item = document.player.currentItem,
               let mix = item.audioMix,
               let duration = try? await item.asset.load(.duration),
               CMTimeCompare(duration, document.duration.cmTime) == 0 {
                previewMix = mix
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(previewMix?.inputParameters.count == 1)
    }

    @Test func freezeKeepsPrimaryAndWebcamOnTheSameResumeBoundary() async throws {
        try await withFixture(frameCount: 90, colorChangesAtFrame: 45) { source, directory in
            let webcam = directory.appending(path: "webcam.mp4")
            try makeFixture(at: webcam, frameCount: 90, colorChangesAtFrame: 45)
            var webcamEffect = WebcamEffect()
            webcamEffect.isEnabled = true
            let snapshot = MediaExportSnapshot(
                projectID: fixedID(1), sourceURL: source, sourceAsset: fixtureAsset(relativePath: source.lastPathComponent),
                canvas: .source, effects: .init(freezeFrame: .init(timeMicroseconds: 1_000_000, durationMicroseconds: 1_000_000), webcam: webcamEffect), webcamURL: webcam
            )
            let destination = directory.appending(path: "synced.mp4")
            _ = try await MediaExportCoordinator().export(snapshot: snapshot, preset: try preset(), destination: destination)

            let output = AVURLAsset(url: destination)
            let generator = AVAssetImageGenerator(asset: output)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let image = try await generator.image(at: CMTime(seconds: 2, preferredTimescale: 600)).image
            let primary = try #require(pixel(image, x: 20, y: 20))
            let webcamFrame = MediaExportVideoComposition.webcamFrame(outputSize: .init(width: 320, height: 240), corner: "BR", isCircular: false)
            let camera = try #require(pixel(image, x: Int(webcamFrame.midX), y: Int(webcamFrame.midY)))
            #expect(primary.r > 180 && primary.g < 80)
            #expect(camera.r > 180 && camera.g < 80)
        }
    }

    @Test func webcamExportUsesCircleMaskOnlyForCircularSetting() async throws {
        try await withFixture { source, directory in
            let webcam = directory.appending(path: "webcam.mp4")
            try makeFixture(at: webcam, frameCount: 60, solidColor: (255, 0, 255))
            var webcamEffect = WebcamEffect()
            webcamEffect.isEnabled = true
            webcamEffect.isCircular = true
            let snapshot = MediaExportSnapshot(projectID: fixedID(1), sourceURL: source,
                sourceAsset: fixtureAsset(relativePath: source.lastPathComponent), canvas: .source,
                effects: .init(webcam: webcamEffect), webcamURL: webcam)
            let destination = directory.appending(path: "circle.mp4")
            _ = try await MediaExportCoordinator().export(snapshot: snapshot, preset: try preset(), destination: destination)

            let image = try await AVAssetImageGenerator(asset: AVURLAsset(url: destination)).image(at: .zero).image
            let frame = MediaExportVideoComposition.webcamFrame(outputSize: .init(width: 320, height: 240), corner: "BR", isCircular: true)
            let center = try #require(pixel(image, x: Int(frame.midX), y: Int(frame.midY)))
            let outside = try #require(pixel(image, x: Int(frame.minX) + 3, y: Int(frame.minY) + 3))
            #expect(center.r > 180 && center.b > 180 && center.g < 80)
            #expect(!(outside.r > 180 && outside.b > 180 && outside.g < 80))

            webcamEffect.isCircular = false
            let rectangularSnapshot = MediaExportSnapshot(projectID: fixedID(1), sourceURL: source,
                sourceAsset: fixtureAsset(relativePath: source.lastPathComponent), canvas: .source,
                effects: .init(webcam: webcamEffect), webcamURL: webcam)
            let rectangularDestination = directory.appending(path: "rectangle.mp4")
            _ = try await MediaExportCoordinator().export(snapshot: rectangularSnapshot, preset: try preset(),
                                                           destination: rectangularDestination)
            let rectangularImage = try await AVAssetImageGenerator(asset: AVURLAsset(url: rectangularDestination)).image(at: .zero).image
            let rectangularFrame = MediaExportVideoComposition.webcamFrame(outputSize: .init(width: 320, height: 240), corner: "BR", isCircular: false)
            let rectangularCorner = try #require(pixel(rectangularImage, x: Int(rectangularFrame.minX) + 3,
                                                       y: Int(rectangularFrame.minY) + 3))
            #expect(rectangularCorner.r > 180 && rectangularCorner.b > 180 && rectangularCorner.g < 80)
        }
    }

    @Test func enabledMissingWebcamFailsExport() async throws {
        try await withFixture { source, directory in
            var webcamEffect = WebcamEffect()
            webcamEffect.isEnabled = true
            let snapshot = MediaExportSnapshot(projectID: fixedID(1), sourceURL: source,
                sourceAsset: fixtureAsset(relativePath: source.lastPathComponent), canvas: .source,
                effects: .init(webcam: webcamEffect), webcamURL: directory.appending(path: "missing.mp4"))
            await #expect(throws: MediaExportError.webcamUnavailable) {
                _ = try await MediaExportCoordinator().export(snapshot: snapshot, preset: try preset(),
                                                               destination: directory.appending(path: "result.mp4"))
            }
        }
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
        colorChangesAtFrame: Int? = nil,
        _ body: (URL, URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AeroshotMediaExport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "fixture.mp4")
        try makeFixture(at: source, frameCount: frameCount, colorChangesAtFrame: colorChangesAtFrame)
        try await body(source, directory)
    }

    private func makeFixture(at url: URL, frameCount: Int, solidColor: (UInt8, UInt8, UInt8)? = nil,
                             colorChangesAtFrame: Int? = nil) throws {
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
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<240 {
                for x in 0..<320 {
                    let offset = y * bytesPerRow + x * 4
                    let top = y < 120
                    let left = x < 160
                    let rgb: (UInt8, UInt8, UInt8)
                    if let solidColor {
                        rgb = solidColor
                    } else if let colorChangesAtFrame {
                        rgb = index < colorChangesAtFrame ? (255, 0, 0) : (0, 255, 0)
                    } else {
                        rgb = switch (top, left) {
                        case (true, true): (255, 0, 0)
                        case (true, false): (0, 255, 0)
                        case (false, true): (0, 0, 255)
                        case (false, false): (255, 255, 0)
                        }
                    }
                    base[offset] = rgb.2
                    base[offset + 1] = rgb.1
                    base[offset + 2] = rgb.0
                    base[offset + 3] = 255
                }
            }
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
