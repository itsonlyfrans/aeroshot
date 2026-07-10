import Foundation
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

        document.updateSelectedOverlay(payload: "Updated", start: 1.5, duration: 3.25)
        #expect(document.model.overlays[0].payload == "Updated")
        let updatedRange = RationalTimeRange(start: try t(3, 2), duration: try t(13, 4))
        #expect(document.model.overlays[0].range == updatedRange)

        document.setAudio(muted: true, gain: 1.5)
        #expect(document.model.audio == .init(isMuted: true, gain: 1.5))
        document.setCrop(.init(x: 0.05, y: 0.05, width: 0.9, height: 0.9))
        #expect(document.model.canvas?.crop == .init(x: 0.05, y: 0.05, width: 0.9, height: 0.9))
        #expect(document.model.validate().isEmpty)
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
