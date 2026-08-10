@preconcurrency import AVFoundation
import Foundation

nonisolated enum MediaCompositionCompilerError: Error, Equatable {
    case invalidModel([MediaModelValidationError])
    case unreadableAsset(UUID)
    case sourceDurationMismatch(UUID)
    case missingDeclaredVideo(UUID)
    case missingDeclaredAudio(UUID)
    case cannotCreateCompositionTrack(AVMediaType)
    case insertionFailed(sliceIndex: Int, mediaType: AVMediaType, reason: String)
}

struct CompiledMediaComposition: @unchecked Sendable {
    let composition: AVMutableComposition
    let audioMix: AVAudioMix?
}

/// Compiles the immutable source references and edit slices into disposable
/// AVFoundation objects. It never writes to, replaces, or mutates a source URL.
struct MediaCompositionCompiler: Sendable {
    func compile(_ model: MediaCompositionModel) async throws -> CompiledMediaComposition {
        let modelErrors = model.validate()
        guard modelErrors.isEmpty else { throw MediaCompositionCompilerError.invalidModel(modelErrors) }

        var loaded: [UUID: LoadedAsset] = [:]
        for source in model.assets where model.slices.contains(where: { $0.sourceAssetID == source.id }) {
            loaded[source.id] = try await load(source)
        }

        let composition = AVMutableComposition()
        let needsVideo = model.slices.contains { loaded[$0.sourceAssetID]?.videoTrack != nil }
        let needsAudio = model.slices.contains { loaded[$0.sourceAssetID]?.audioTrack != nil }
        let videoTrack = needsVideo ? composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) : nil
        let audioTrack = needsAudio ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) : nil
        if needsVideo, videoTrack == nil { throw MediaCompositionCompilerError.cannotCreateCompositionTrack(.video) }
        if needsAudio, audioTrack == nil { throw MediaCompositionCompilerError.cannotCreateCompositionTrack(.audio) }

        var cursor = CMTime.zero
        for (index, slice) in model.slices.enumerated() {
            guard let source = loaded[slice.sourceAssetID] else {
                throw MediaCompositionCompilerError.unreadableAsset(slice.sourceAssetID)
            }
            let range = CMTimeRange(start: slice.sourceRange.start.cmTime, duration: slice.sourceRange.duration.cmTime)
            if let sourceTrack = source.videoTrack, let videoTrack {
                do { try videoTrack.insertTimeRange(range, of: sourceTrack, at: cursor) }
                catch { throw MediaCompositionCompilerError.insertionFailed(sliceIndex: index, mediaType: .video, reason: error.localizedDescription) }
                if videoTrack.segments.count == 1 { videoTrack.preferredTransform = source.preferredTransform }
            }
            if let sourceTrack = source.audioTrack, let audioTrack {
                do { try audioTrack.insertTimeRange(range, of: sourceTrack, at: cursor) }
                catch { throw MediaCompositionCompilerError.insertionFailed(sliceIndex: index, mediaType: .audio, reason: error.localizedDescription) }
            }
            cursor = CMTimeAdd(cursor, range.duration)
        }

        let audioMix = Self.audioMix(for: audioTrack, audio: model.audio, sourceDuration: model.duration,
                                     timing: .init(freezeFrame: nil))
        return CompiledMediaComposition(composition: composition, audioMix: audioMix)
    }

    static func audioMix(for track: AVAssetTrack?, audio: AudioState, sourceDuration: RationalTime,
                         timing: MediaOutputTiming) -> AVAudioMix? {
        guard let track else { return nil }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        let targetVolume: Float = audio.isMuted ? 0 : audio.gain
        parameters.setVolume(targetVolume, at: .zero)
        let sourceDurationMicroseconds = Int64(sourceDuration.seconds * 1_000_000)
        addRamp(from: 0, to: min(sourceDurationMicroseconds, Int64(audio.fadeIn.seconds * 1_000_000)),
                startVolume: 0, endVolume: targetVolume, timing: timing, to: parameters)
        let fadeOutDuration = min(sourceDurationMicroseconds, Int64(audio.fadeOut.seconds * 1_000_000))
        addRamp(from: sourceDurationMicroseconds - fadeOutDuration, to: sourceDurationMicroseconds,
                startVolume: targetVolume, endVolume: 0, timing: timing, to: parameters)
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    private static func addRamp(from sourceStart: Int64, to sourceEnd: Int64, startVolume: Float, endVolume: Float,
                                timing: MediaOutputTiming, to parameters: AVMutableAudioMixInputParameters) {
        let sourceDuration = sourceEnd - sourceStart
        guard sourceDuration > 0 else { return }
        for segment in timing.audioSegments(from: sourceStart, through: sourceEnd) {
            let startFraction = Float(segment.sourceStart - sourceStart) / Float(sourceDuration)
            let endFraction = Float(segment.sourceEnd - sourceStart) / Float(sourceDuration)
            let start = startVolume + (endVolume - startVolume) * startFraction
            let end = startVolume + (endVolume - startVolume) * endFraction
            parameters.setVolumeRamp(fromStartVolume: start, toEndVolume: end,
                timeRange: .init(start: .init(value: segment.outputStart, timescale: 1_000_000),
                                 duration: .init(value: segment.outputEnd - segment.outputStart, timescale: 1_000_000)))
        }
    }

    private func load(_ source: MediaSourceAsset) async throws -> LoadedAsset {
        let asset = AVURLAsset(url: source.url)
        let duration: CMTime
        let videoTracks: [AVAssetTrack]
        let audioTracks: [AVAssetTrack]
        let preferredTransform: CGAffineTransform
        do {
            duration = try await asset.load(.duration)
            videoTracks = try await asset.loadTracks(withMediaType: .video)
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
            preferredTransform = try await videoTracks.first?.load(.preferredTransform) ?? .identity
        } catch {
            throw MediaCompositionCompilerError.unreadableAsset(source.id)
        }
        guard duration.isNumeric, CMTimeCompare(duration, source.duration.cmTime) >= 0 else {
            throw MediaCompositionCompilerError.sourceDurationMismatch(source.id)
        }
        if source.hasVideo, videoTracks.isEmpty { throw MediaCompositionCompilerError.missingDeclaredVideo(source.id) }
        if source.hasAudio, audioTracks.isEmpty { throw MediaCompositionCompilerError.missingDeclaredAudio(source.id) }
        // Retain the AVAsset for as long as its tracks are used. AVAssetTrack does
        // not independently guarantee the backing reader's lifetime.
        return LoadedAsset(asset: asset, videoTrack: videoTracks.first, audioTrack: audioTracks.first, preferredTransform: preferredTransform)
    }
}

private struct LoadedAsset: @unchecked Sendable {
    let asset: AVURLAsset
    let videoTrack: AVAssetTrack?
    let audioTrack: AVAssetTrack?
    let preferredTransform: CGAffineTransform
}
