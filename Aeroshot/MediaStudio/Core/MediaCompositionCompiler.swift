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

        let audioMix: AVAudioMix?
        if let audioTrack {
            let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
            let targetVolume: Float = model.audio.isMuted ? 0 : model.audio.gain
            parameters.setVolume(targetVolume, at: .zero)
            if model.audio.fadeIn > .zero {
                parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: targetVolume,
                    timeRange: CMTimeRange(start: .zero, duration: model.audio.fadeIn.cmTime))
            }
            if model.audio.fadeOut > .zero {
                let start = CMTimeSubtract(model.duration.cmTime, model.audio.fadeOut.cmTime)
                parameters.setVolumeRamp(fromStartVolume: targetVolume, toEndVolume: 0,
                    timeRange: CMTimeRange(start: start, duration: model.audio.fadeOut.cmTime))
            }
            let mutableMix = AVMutableAudioMix()
            mutableMix.inputParameters = [parameters]
            audioMix = mutableMix
        } else {
            audioMix = nil
        }
        return CompiledMediaComposition(composition: composition, audioMix: audioMix)
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
