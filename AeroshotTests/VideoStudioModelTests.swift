import Foundation
import CoreGraphics
import Testing
@testable import Aeroshot

@Suite(.serialized)
@MainActor
struct VideoStudioModelTests {
    private let assetID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test func selectionRequiresOrderedBoundaries() throws {
        var selection = VideoStudioSelection()
        selection.inPoint = try t(4)
        selection.outPoint = try t(2)
        #expect(selection.range == nil)
        selection.outPoint = try t(7)
        let expectedRange = RationalTimeRange(start: try t(4), duration: try t(3))
        #expect(selection.range == expectedRange)
    }

    @Test func commandsSplitDeleteAndUndoDeterministically() throws {
        let document = try makeDocument()
        document.seek(to: try t(4))
        document.perform(.split)
        let expectedSplitDurations = [try t(4), try t(6)]
        #expect(document.model.slices.map(\.sourceRange.duration) == expectedSplitDurations)
        document.perform(.undo)
        #expect(document.model.slices.count == 1)

        document.seek(to: try t(2)); document.perform(.setIn)
        document.seek(to: try t(5)); document.perform(.setOut)
        document.perform(.deleteSelection)
        let seven = try t(7)
        let ten = try t(10)
        #expect(document.model.duration == seven)
        #expect(document.model.slices.map(\.sourceRange) == [
            .init(start: .zero, duration: try t(2)),
            .init(start: try t(5), duration: try t(5)),
        ])
        document.perform(.undo)
        #expect(document.model.duration == ten)
        document.perform(.redo)
        #expect(document.model.duration == seven)
    }

    @Test func calloutCanvasAndAudioCommandsCarryRealState() throws {
        let document = try makeDocument()
        document.seek(to: try t(8))
        document.addCallout(text: "Watch this")
        let overlay = try #require(document.model.overlays.first)
        #expect(overlay.payload == "Watch this")
        let initialRange = RationalTimeRange(start: try t(8), duration: try t(2))
        #expect(overlay.range == initialRange)
        #expect(overlay.bounds == .legacyCallout)
        #expect(overlay.color == .legacyCallout)

        document.updateSelectedOverlay(payload: "Updated", start: 1.5, duration: 3.25)
        #expect(document.model.overlays[0].payload == "Updated")
        let updatedRange = RationalTimeRange(start: try t(3, 2), duration: try t(13, 4))
        #expect(document.model.overlays[0].range == updatedRange)

        document.setAudio(muted: true, gain: 1.5, fadeIn: 0.5, fadeOut: 1)
        #expect(document.model.audio == .init(isMuted: true, gain: 1.5, fadeIn: try t(1, 2), fadeOut: try t(1)))
        document.setCrop(.init(x: 0.05, y: 0.05, width: 0.9, height: 0.9))
        #expect(document.model.canvas?.crop == .init(x: 0.05, y: 0.05, width: 0.9, height: 0.9))
        document.setEffects(events: [
            .init(kind: .cursor, timeMicroseconds: 1_000_000, x: 0.25, y: 0.75),
            .init(kind: .click, timeMicroseconds: 1_000_000, x: 0.4, y: 0.6),
        ])
        document.seek(to: try t(1))
        document.setEffects(cursorEmphasis: 1.5, clickEmphasis: 1)
        #expect(document.activeCursorEvent?.x == 0.25)
        #expect(document.activeClickEvents.count == 1)
        #expect(document.model.validate().isEmpty)
    }

    @Test func overlayVisualsValidateMapClampAndUndoOncePerGesture() throws {
        let document = try makeDocument()
        document.addCallout(text: "Place me")
        let id = try #require(document.selectedOverlayID)
        let editedBounds = NormalizedOverlayBounds(x: 0.2, y: 0.3, width: 0.4, height: 0.25)
        let editedColor = SRGBAColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 0.7)
        document.updateSelectedOverlayVisual(bounds: editedBounds, color: editedColor)

        let command = try #require(VideoStudioDocument.overlayManifest(from: document.model).first)
        #expect(command.geometry.bounds == .init(x: 0.2, y: 0.3, width: 0.4, height: 0.25))
        #expect(command.appearance.strokeRGBA == editedColor.components)

        let contentRect = VideoStudioPreviewGeometry.aspectFitContentRect(
            container: .init(width: 1_000, height: 1_000), source: .init(width: 1_920, height: 1_080)
        )
        #expect(abs(contentRect.minX) < 0.000_001)
        #expect(abs(contentRect.minY - 218.75) < 0.000_001)
        #expect(abs(contentRect.width - 1_000) < 0.000_001)
        #expect(abs(contentRect.height - 562.5) < 0.000_001)
        let moved = VideoStudioPreviewGeometry.moved(
            editedBounds, translation: .init(width: 9_999, height: -9_999), in: contentRect
        )
        #expect(moved.x == 0.6)
        #expect(moved.y == 0)
        let resized = VideoStudioPreviewGeometry.resized(
            editedBounds, corner: .topLeft, translation: .init(width: 9_999, height: 9_999), in: contentRect
        )
        #expect(resized.width >= VideoStudioPreviewGeometry.minimumOverlaySize)
        #expect(resized.height >= VideoStudioPreviewGeometry.minimumOverlaySize)
        for corner in OverlayResizeCorner.allCases {
            let candidate = VideoStudioPreviewGeometry.resized(
                editedBounds, corner: corner, translation: .init(width: 24, height: 18), in: contentRect
            )
            #expect(candidate.isValid)
            #expect(candidate.width >= VideoStudioPreviewGeometry.minimumOverlaySize)
            #expect(candidate.height >= VideoStudioPreviewGeometry.minimumOverlaySize)
            switch corner {
            case .topLeft:
                #expect(candidate.x + candidate.width == editedBounds.x + editedBounds.width)
                #expect(candidate.y + candidate.height == editedBounds.y + editedBounds.height)
            case .topRight:
                #expect(candidate.x == editedBounds.x)
                #expect(candidate.y + candidate.height == editedBounds.y + editedBounds.height)
            case .bottomLeft:
                #expect(candidate.x + candidate.width == editedBounds.x + editedBounds.width)
                #expect(candidate.y == editedBounds.y)
            case .bottomRight:
                #expect(candidate.x == editedBounds.x)
                #expect(candidate.y == editedBounds.y)
            }
        }
        for corner in OverlayResizeCorner.allCases {
            let subminimumAtEdge = NormalizedOverlayBounds(x: 0.98, y: 0.98, width: 0.01, height: 0.01)
            let repaired = VideoStudioPreviewGeometry.resized(
                subminimumAtEdge, corner: corner, translation: .zero, in: contentRect
            )
            #expect(repaired.isValid)
            #expect(repaired.width >= VideoStudioPreviewGeometry.minimumOverlaySize)
            #expect(repaired.height >= VideoStudioPreviewGeometry.minimumOverlaySize)
        }

        _ = document.beginOverlayVisualGesture(id)
        document.previewOverlayBounds(moved, for: id)
        document.previewOverlayBounds(.init(x: 0.5, y: 0.1, width: 0.4, height: 0.25), for: id)
        document.commitOverlayVisualGesture(id)
        #expect(document.model.overlays[0].bounds.x == 0.5)
        document.perform(.undo)
        #expect(document.model.overlays[0].bounds == editedBounds)
        document.perform(.undo)
        #expect(document.model.overlays[0].bounds == .legacyCallout)
    }

    @Test func malformedOverlayVisualStateIsRejected() throws {
        let document = try makeDocument()
        document.addCallout()
        var model = document.model
        model.overlays[0].bounds.x = .nan
        model.overlays[0].color.alpha = 1.1
        #expect(model.validate().contains(.invalidOverlayBounds(model.overlays[0].id)))
        #expect(model.validate().contains(.invalidOverlayColor(model.overlays[0].id)))
    }

    @Test func nonFiniteCropStateIsRejected() throws {
        var model = try makeDocument().model
        for value in [Double.nan, .infinity, -.infinity] {
            model.canvas = .init(crop: .init(x: value, y: 0, width: 1, height: 1), width: 1_920, height: 1_080)
            #expect(model.validate().contains(.invalidCrop))
        }
    }

    @Test func cropLayoutMapsVisibleEffectsAndOmitsOutsideEvents() throws {
        let document = try makeDocument()
        document.setCrop(.init(x: 0.25, y: 0.25, width: 0.5, height: 0.25))
        let outsideCursorEvents = (0..<5_001).map {
            RecordedEffectEvent(kind: .cursor, timeMicroseconds: Int64($0), x: 0.1, y: 0.1)
        }
        document.setEffects(events: outsideCursorEvents + [
            .init(kind: .cursor, timeMicroseconds: 1_000_000, x: 0.5, y: 0.375),
            .init(kind: .click, timeMicroseconds: 1_000_000, x: 0.1, y: 0.1),
        ], cursorEmphasis: 1, clickEmphasis: 1)

        let overlays = VideoStudioDocument.overlayManifest(
            from: document.model,
            sourceSize: CGSize(width: 1_920, height: 1_080)
        )
        let effect = try #require(overlays.first)
        #expect(overlays.count == 1)
        #expect(effect.content == "effect.cursor")
        #expect(abs(effect.geometry.bounds.x + effect.geometry.bounds.width / 2 - 0.5) < 0.000_001)
        #expect(abs(effect.geometry.bounds.y + effect.geometry.bounds.height / 2 - 0.5) < 0.000_001)
    }

    @Test func exportOutputSizeNormalizationIsSharedAndRejectsUndersizedCanvas() {
        #expect(VideoStudioDocument.normalizedOutputSize(CGSize(width: 1_921, height: 1_081))
                == CGSize(width: 1_920, height: 1_080))
        #expect(VideoStudioDocument.normalizedOutputSize(CGSize(width: 1, height: 1_080)) == nil)
        #expect(VideoStudioDocument.normalizedOutputSize(CGSize(width: CGFloat.infinity, height: 1_080)) == nil)
    }

    @Test func commandAndTimecodeContractsStayStable() throws {
        #expect(VideoStudioCommand.togglePlayback == .togglePlayback)
        let time = try t(65) + t(12, 30)
        let rate = try t(30)
        #expect(PlaybackMath.timecode(time, frameRate: rate) == "00:01:05:12")
        let document = try makeDocument()
        document.perform(.deleteSelection)
        #expect(document.statusMessage == VideoStudioDocumentError.invalidSelection.localizedDescription)
    }

    @Test func undoHistoryIsBoundedAndDropsOldestFirst() throws {
        let document = try makeDocument()
        let extra = 10
        for index in 0..<(VideoStudioDocument.undoDepthLimit + extra) {
            document.addCallout(text: "Callout \(index)")
        }
        #expect(document.model.overlays.count == VideoStudioDocument.undoDepthLimit + extra)

        var undoCount = 0
        while document.canUndo {
            document.perform(.undo)
            undoCount += 1
        }
        #expect(undoCount == VideoStudioDocument.undoDepthLimit)
        // The oldest `extra` mutations were evicted, so they are unrecoverable.
        #expect(document.model.overlays.count == extra)
    }

    private func makeDocument() throws -> VideoStudioDocument {
        let package = FileManager.default.temporaryDirectory.appending(path: "video-studio-model-tests")
        let asset = MediaSourceAsset(id: assetID, url: package.appending(path: "source.mp4"), duration: try t(10), hasVideo: true, hasAudio: true)
        let model = MediaCompositionModel(assets: [asset], slices: [.init(sourceAssetID: assetID, sourceRange: .init(start: .zero, duration: try t(10)))])
        let projectAsset = AeroProjectAsset(id: assetID, relativePath: "assets/originals/source.mp4", sha256: "test", byteCount: 1,
            isImmutableOriginal: true, metadata: .init(mediaType: .video, pixelSize: try AeroPixelSize(width: 1920, height: 1080),
                                                       duration: try AeroMediaTime(value: 10, timescale: 1), nominalFrameRate: try AeroMediaTime(value: 30, timescale: 1),
                                                       colorSpaceName: nil, hasAudio: true))
        return VideoStudioDocument(model: model, manifest: .init(assets: [projectAsset], primarySourceAssetID: assetID), packageURL: package, frameRate: try t(30))
    }

    private func t(_ numerator: Int64, _ denominator: Int32 = 1) throws -> RationalTime { try RationalTime(numerator, denominator) }
}
