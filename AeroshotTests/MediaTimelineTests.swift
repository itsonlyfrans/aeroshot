import AVFoundation
import Testing
@testable import Aeroshot

@Suite(.serialized)
@MainActor
struct MediaTimelineTests {
    private let assetID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func t(_ numerator: Int64, _ denominator: Int32 = 1) -> RationalTime {
        try! RationalTime(numerator, denominator)
    }

    private func model(duration: Int64 = 10) -> MediaCompositionModel {
        let asset = MediaSourceAsset(id: assetID, url: URL(fileURLWithPath: "/tmp/source.mov"), duration: t(duration))
        return MediaCompositionModel(
            assets: [asset],
            slices: [MediaSlice(sourceAssetID: assetID, sourceRange: RationalTimeRange(start: .zero, duration: t(duration)))]
        )
    }

    @Test func rationalTimeNormalizesAndCalculatesExactly() throws {
        #expect(try RationalTime(2, 4) == RationalTime(1, 2))
        #expect(try t(1, 3) + t(1, 6) == t(1, 2))
        #expect(try t(5, 6) - t(1, 3) == t(1, 2))
        #expect(throws: RationalTimeError.invalidDenominator) { try RationalTime(1, 0) }
    }

    @Test func splitPreservesDurationAndMappingAtBoundaries() throws {
        let original = model()
        #expect(try original.split(at: .zero) == original)
        #expect(try original.split(at: t(10)) == original)

        let split = try original.split(at: t(4))
        #expect(split.slices.map(\.sourceRange.duration) == [t(4), t(6)])
        #expect(split.duration == original.duration)
        #expect(split.sourcePosition(at: t(4)) == SourcePosition(assetID: assetID, time: t(4)))
    }

    @Test func trimAcrossSlicesRipplesToZero() throws {
        let split = try model().split(at: t(4))
        let trimmed = try split.trim(to: RationalTimeRange(start: t(2), duration: t(6)))
        #expect(trimmed.duration == t(6))
        #expect(trimmed.slices.map(\.sourceRange) == [
            RationalTimeRange(start: t(2), duration: t(2)),
            RationalTimeRange(start: t(4), duration: t(4)),
        ])
        #expect(trimmed.sourcePosition(at: .zero)?.time == t(2))
    }

    @Test func selectedRangeDeletionIsFirstSliceOnlyAndRipples() throws {
        let deleted = try model().deleteSelectedRange(RationalTimeRange(start: t(3), duration: t(2)))
        #expect(deleted.duration == t(8))
        #expect(deleted.slices.map(\.sourceRange) == [
            RationalTimeRange(start: .zero, duration: t(3)),
            RationalTimeRange(start: t(5), duration: t(5)),
        ])
        #expect(deleted.sourcePosition(at: t(3))?.time == t(5))
        #expect(throws: MediaTimelineError.selectionOutsideFirstSlice) {
            try deleted.deleteSelectedRange(RationalTimeRange(start: t(4), duration: t(1)))
        }
    }

    @Test func zeroDurationAndInvalidRangesAreHandledDeterministically() throws {
        let original = model()
        #expect(try original.deleteSelectedRange(RationalTimeRange(start: t(2), duration: .zero)) == original)
        #expect(try original.trim(to: RationalTimeRange(start: t(5), duration: .zero)).slices.isEmpty)
        #expect(throws: MediaTimelineError.rangeOutsideComposition) {
            try original.trim(to: RationalTimeRange(start: t(9), duration: t(2)))
        }
    }

    @Test func mappingIsReversibleForEveryIntegerSampleAfterMultipleEdits() throws {
        let edited = try model(duration: 20)
            .deleteSelectedRange(RationalTimeRange(start: t(3), duration: t(2)))
            .trim(to: RationalTimeRange(start: t(1), duration: t(15)))
            .split(at: t(8))

        for second in 0..<15 {
            let compositionTime = t(Int64(second))
            let source = try #require(edited.sourcePosition(at: compositionTime))
            #expect(edited.compositionTime(for: source) == compositionTime)
        }
    }

    @Test func deterministicGeneratedEditsPreserveTimelineInvariants() throws {
        for seed in 1...100 {
            let duration = Int64(20 + seed % 17)
            let deleteStart = Int64(seed % 7)
            let deleteDuration = Int64(1 + seed % 5)
            let edited = try model(duration: duration).deleteSelectedRange(
                RationalTimeRange(start: t(deleteStart), duration: t(deleteDuration))
            )
            #expect(edited.duration == t(duration - deleteDuration))
            #expect(edited.slices.allSatisfy { $0.sourceRange.duration > .zero })
            #expect(edited.validate().isEmpty)
        }
    }

    @Test func trimAndDeleteRetimeRecordedEffectEvents() throws {
        var value = model(duration: 10)
        value.effects.events = [
            .init(kind: .cursor, timeMicroseconds: 1_000_000, x: 0.1, y: 0.1),
            .init(kind: .click, timeMicroseconds: 4_000_000, x: 0.2, y: 0.2),
            .init(kind: .cursor, timeMicroseconds: 8_000_000, x: 0.3, y: 0.3),
        ]
        let trimmed = try value.trim(to: .init(start: t(2), duration: t(6)))
        #expect(trimmed.effects.events.map(\.timeMicroseconds) == [2_000_000, 6_000_000])
        let deleted = try value.deleteSelectedRange(.init(start: t(3), duration: t(2)))
        #expect(deleted.effects.events.map(\.timeMicroseconds) == [1_000_000, 6_000_000])
    }

    @Test func playbackUtilitiesAreExactAndTransportIntentIsBounded() throws {
        #expect(try PlaybackMath.frameStep(frameRate: RationalTime(30_000, 1_001)) == RationalTime(1_001, 30_000))
        #expect(PlaybackMath.timecode(try t(3_661) + t(15, 30), frameRate: t(30)) == "01:01:01:15")
        #expect(TransportState().applying(.playForward).rate == 1)
        #expect(TransportState(rate: 2).applying(.playForward).rate == 4)
        #expect(TransportState(rate: -4).applying(.playReverse).rate == -8)
        #expect(TransportState(rate: 8).applying(.playForward).rate == 8)
        #expect(TransportState(rate: 2).applying(.pause).rate == 0)
    }

    @Test func ancillaryModelsRoundTripThroughCodable() throws {
        var value = model()
        value.overlays = [.init(kind: .callout, range: .init(start: t(1), duration: t(2)), payload: "Look here")]
        value.canvas = .init(crop: .init(x: 0.1, y: 0.2, width: 0.7, height: 0.6), width: 1_920, height: 1_080)
        value.audio = .init(isMuted: false, gain: 0.75, fadeIn: t(1), fadeOut: t(2))
        let decoded = try JSONDecoder().decode(MediaCompositionModel.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)

        let thumbnail = ThumbnailRequest(assetID: assetID, times: [t(1), t(2)], maximumSize: .init(width: 320, height: 180))
        let waveform = WaveformRequest(assetID: assetID, range: .init(start: .zero, duration: t(10)), sampleCount: 200)
        #expect(thumbnail.maximumSize.width == 320)
        #expect(waveform.sampleCount == 200)

        let legacyAudio = try JSONDecoder().decode(AudioState.self, from: Data(#"{"isMuted":true,"gain":0.5}"#.utf8))
        #expect(legacyAudio == .init(isMuted: true, gain: 0.5))
    }

    @Test func validationRejectsMissingAssetsAndOutOfBoundsRanges() {
        let missing = MediaCompositionModel(assets: [], slices: [
            .init(sourceAssetID: assetID, sourceRange: .init(start: .zero, duration: t(1))),
        ])
        #expect(missing.validate() == [.missingAsset(assetID)])

        var outside = model()
        outside.slices[0].sourceRange = .init(start: t(9), duration: t(2))
        #expect(outside.validate() == [.sourceRangeOutsideAsset(sliceIndex: 0)])
    }

    @Test func compilerRejectsInvalidModelBeforeReadingMedia() async {
        let invalid = MediaCompositionModel(assets: [], slices: [
            .init(sourceAssetID: assetID, sourceRange: .init(start: .zero, duration: t(1))),
        ])
        await #expect(throws: MediaCompositionCompilerError.invalidModel([.missingAsset(assetID)])) {
            try await MediaCompositionCompiler().compile(invalid)
        }
    }

    @Test func compilerRejectsUnreadableMediaDeterministically() async {
        let source = MediaSourceAsset(
            id: assetID,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).mov"),
            duration: t(1),
            hasVideo: false,
            hasAudio: false
        )
        let value = MediaCompositionModel(
            assets: [source],
            slices: [.init(sourceAssetID: assetID, sourceRange: .init(start: .zero, duration: t(1)))]
        )
        await #expect(throws: MediaCompositionCompilerError.unreadableAsset(assetID)) {
            try await MediaCompositionCompiler().compile(value)
        }
    }

    @Test func compilerBuildsRealCompositionWithoutMutatingSource() async throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("aeroshot-media-core-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try writeVideoFixture(to: sourceURL)
        let originalBytes = try Data(contentsOf: sourceURL)
        let source = MediaSourceAsset(id: assetID, url: sourceURL, duration: t(1), hasVideo: false, hasAudio: true)
        let value = MediaCompositionModel(
            assets: [source],
            slices: [.init(sourceAssetID: assetID, sourceRange: .init(start: t(1, 5), duration: t(3, 5)))],
            audio: .init(isMuted: true, gain: 0.5, fadeIn: t(1, 10), fadeOut: t(1, 10))
        )

        let compiled = try await MediaCompositionCompiler().compile(value)
        #expect(CMTimeCompare(compiled.composition.duration, t(3, 5).cmTime) == 0)
        #expect(try Data(contentsOf: sourceURL) == originalBytes)
        #expect(compiled.composition.tracks(withMediaType: .audio).count == 1)
        let envelope = try await AudioWaveformGenerator().samples(from: sourceURL, sampleCount: 32)
        #expect(envelope.count == 32)
        #expect(envelope.allSatisfy { $0 == 0 })
    }

    private func writeVideoFixture(to url: URL) throws {
        let sampleRate: UInt32 = 8_000
        let dataSize: UInt32 = sampleRate * 2
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: (36 + dataSize).littleEndian, Array.init))
        data.append("WAVEfmt ".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: (sampleRate * 2).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian, Array.init))
        data.append("data".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
        data.append(Data(count: Int(dataSize)))
        try data.write(to: url, options: .atomic)
    }
}
