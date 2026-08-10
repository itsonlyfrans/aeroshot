@preconcurrency import AVFoundation
import Foundation

nonisolated enum MediaExportError: Error, Equatable, Sendable, LocalizedError {
    case missingSourceAsset
    case invalidSourcePath
    case sourceUnavailable
    case sourceHasNoVideo
    case invalidFreezeFrame
    case webcamUnavailable
    case invalidResolution
    case invalidFrameRate
    case unsupportedPreset
    case cannotCreateSession
    case destinationIsDirectory
    case exportFailed(String)
    case cancelled
    case atomicCommitFailed(String)
    case unsupportedOfflineOverlay(UUID)
    case codecMismatch(expected: MediaExportCodec)

    var errorDescription: String? {
        self == .webcamUnavailable
            ? "The webcam recording is unavailable. Restore the file or turn off the webcam before export."
            : nil
    }
}

nonisolated enum MediaEncoderEvidence: Equatable, Sendable {
    /// AVAssetExportSession does not disclose the selected hardware encoder.
    /// We report the requested codec and this limitation instead of guessing.
    case verifiedOutputCodec(
        codec: MediaExportCodec,
        hardwareUseObservable: Bool,
        fallbackObservable: Bool
    )
}

nonisolated struct MediaExportResult: Equatable, Sendable {
    let destination: URL
    let byteCount: Int64
    let codec: MediaExportCodec
    let colorPolicy: MediaExportColorPolicy
    let encoderEvidence: MediaEncoderEvidence
}

private nonisolated final class MediaExportSessionBox: @unchecked Sendable {
    let value: AVAssetExportSession
    init(_ value: AVAssetExportSession) { self.value = value }
}

actor MediaExportCoordinator {
    typealias ProgressHandler = @Sendable (Double) async -> Void

    func export(
        snapshot: MediaExportSnapshot,
        preset: MediaExportPreset,
        destination: URL,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> MediaExportResult {
        guard !Task.isCancelled else { throw MediaExportError.cancelled }
        try preset.validate()
        guard FileManager.default.fileExists(atPath: snapshot.sourceURL.path) else {
            throw MediaExportError.sourceUnavailable
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw MediaExportError.destinationIsDirectory
        }

        let partial = Self.partialURL(for: destination)
        try? FileManager.default.removeItem(at: partial)
        defer { try? FileManager.default.removeItem(at: partial) }
        let clickURL = partial.deletingPathExtension().appendingPathExtension("click.wav")
        defer { try? FileManager.default.removeItem(at: clickURL) }
        let source = AVURLAsset(url: snapshot.sourceURL)
        let asset = try await Self.renderAsset(source, snapshot: snapshot, clickURL: clickURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset.avPresetName) else {
            throw MediaExportError.unsupportedPreset
        }
        session.videoComposition = try await MediaExportVideoComposition.make(
            asset: asset,
            snapshot: snapshot,
            preset: preset
        )
        let sessionBox = MediaExportSessionBox(session)
        if let range = snapshot.effectiveSourceRange {
            session.timeRange = CMTimeRange(
                start: CMTime(value: range.start.value, timescale: range.start.timescale),
                duration: CMTime(value: range.duration.value, timescale: range.duration.timescale)
            )
        }
        // Compiling here proves export consumes precisely the captured snapshot.
        // A future compositor can attach the resulting command layers without
        // changing the preview/export boundary.
        _ = MediaOverlayCompiler.compile(snapshot)
        await progress(0)
        let reporter = Task.detached {
            while !Task.isCancelled {
                await progress(Double(sessionBox.value.progress))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        defer { reporter.cancel() }

        do {
            try await withTaskCancellationHandler {
                try await sessionBox.value.export(to: partial, as: .mp4)
            } onCancel: {
                sessionBox.value.cancelExport()
            }
        } catch is CancellationError {
            throw MediaExportError.cancelled
        } catch {
            if Task.isCancelled || sessionBox.value.status == .cancelled { throw MediaExportError.cancelled }
            throw MediaExportError.exportFailed(error.localizedDescription)
        }
        guard !Task.isCancelled else { throw MediaExportError.cancelled }
        guard try await Self.outputCodec(at: partial) == preset.codec else {
            throw MediaExportError.codecMismatch(expected: preset.codec)
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: partial)
            } else {
                try FileManager.default.moveItem(at: partial, to: destination)
            }
        } catch {
            throw MediaExportError.atomicCommitFailed(error.localizedDescription)
        }
        await progress(1)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        return MediaExportResult(
            destination: destination,
            byteCount: attributes[.size] as? Int64 ?? 0,
            codec: preset.codec,
            colorPolicy: .rec709SDR,
            encoderEvidence: .verifiedOutputCodec(
                codec: preset.codec,
                hardwareUseObservable: false,
                fallbackObservable: false
            )
        )
    }

    /// Hidden sibling of the destination used as the atomic write target.
    /// The UUID keeps concurrent exports into the same directory from
    /// colliding on one partial file.
    nonisolated static func partialURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent()
            .appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).partial.mp4")
    }

    /// Uses the same held frame for preview and export. The source stays immutable.
    nonisolated static func applyingFreeze(to asset: AVAsset, freezeFrame: FreezeFrameEffect?) async throws -> AVAsset {
        guard let freezeFrame else { return asset }
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaExportError.sourceHasNoVideo
        }
        let duration = try await asset.load(.duration)
        let sourceDuration = duration.convertScale(1_000_000, method: .roundTowardZero).value
        guard freezeFrame.durationMicroseconds > 0, freezeFrame.durationMicroseconds <= 10_000_000,
              freezeFrame.timeMicroseconds >= 0, freezeFrame.timeMicroseconds <= sourceDuration else {
            throw MediaExportError.invalidFreezeFrame
        }
        let freezeTime = CMTime(value: freezeFrame.timeMicroseconds, timescale: 1_000_000)
        let frameDuration = CMTime(value: 1, timescale: max(1, Int32((try await sourceVideo.load(.nominalFrameRate)).rounded())))
        let frame = CMTimeMinimum(frameDuration, duration)
        let frameStart = CMTimeMinimum(freezeTime, CMTimeSubtract(duration, frame))
        guard CMTimeCompare(frame, .zero) > 0, CMTimeCompare(frameStart, .zero) >= 0 else {
            throw MediaExportError.invalidFreezeFrame
        }
        let hold = CMTime(value: freezeFrame.durationMicroseconds, timescale: 1_000_000)
        let heldDuration = CMTimeAdd(frame, hold)
        let tailStart = CMTimeAdd(frameStart, frame)
        let tailDuration = CMTimeSubtract(duration, tailStart)
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: sourceVideo.trackID) else {
            throw MediaExportError.cannotCreateSession
        }
        video.preferredTransform = try await sourceVideo.load(.preferredTransform)
        if frameStart > .zero { try video.insertTimeRange(.init(start: .zero, duration: frameStart), of: sourceVideo, at: .zero) }
        try video.insertTimeRange(.init(start: frameStart, duration: frame), of: sourceVideo, at: frameStart)
        video.scaleTimeRange(.init(start: frameStart, duration: frame), toDuration: heldDuration)
        if tailDuration > .zero { try video.insertTimeRange(.init(start: tailStart, duration: tailDuration), of: sourceVideo, at: CMTimeAdd(frameStart, heldDuration)) }
        for sourceAudio in try await asset.loadTracks(withMediaType: .audio) {
            guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw MediaExportError.cannotCreateSession
            }
            if frameStart > .zero { try audio.insertTimeRange(.init(start: .zero, duration: frameStart), of: sourceAudio, at: .zero) }
            try audio.insertTimeRange(.init(start: frameStart, duration: frame), of: sourceAudio, at: frameStart)
            if tailDuration > .zero { try audio.insertTimeRange(.init(start: tailStart, duration: tailDuration), of: sourceAudio, at: CMTimeAdd(frameStart, heldDuration)) }
        }
        return composition
    }

    private nonisolated static func renderAsset(_ source: AVAsset, snapshot: MediaExportSnapshot, clickURL: URL) async throws -> AVAsset {
        let frozen = try await applyingFreeze(to: source, freezeFrame: snapshot.effects.freezeFrame)
        let duration = try await frozen.load(.duration)
        guard let sourceVideo = try await frozen.loadTracks(withMediaType: .video).first else {
            throw MediaExportError.sourceHasNoVideo
        }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MediaExportError.cannotCreateSession
        }
        try video.insertTimeRange(.init(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        video.preferredTransform = try await sourceVideo.load(.preferredTransform)
        for sourceAudio in try await frozen.loadTracks(withMediaType: .audio) {
            guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw MediaExportError.cannotCreateSession
            }
            try audio.insertTimeRange(.init(start: .zero, duration: duration), of: sourceAudio, at: .zero)
        }
        if snapshot.effects.webcam.isEnabled, let webcamURL = snapshot.webcamURL,
           FileManager.default.fileExists(atPath: webcamURL.path) {
            let webcamAsset = AVURLAsset(url: webcamURL)
            do {
                guard try await webcamAsset.load(.isReadable) else {
                    throw MediaExportError.webcamUnavailable
                }
                let frozenWebcam = try await Self.applyingFreeze(to: webcamAsset, freezeFrame: snapshot.effects.freezeFrame)
                guard let webcamSource = try await frozenWebcam.loadTracks(withMediaType: .video).first,
                      let webcam = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw MediaExportError.webcamUnavailable
                }
                let webcamDuration = try await frozenWebcam.load(.duration)
                let usable = CMTimeMinimum(duration, webcamDuration)
                guard usable > .zero else { throw MediaExportError.webcamUnavailable }
                try webcam.insertTimeRange(.init(start: .zero, duration: usable), of: webcamSource, at: .zero)
                webcam.preferredTransform = try await webcamSource.load(.preferredTransform)
            } catch let error as MediaExportError {
                throw error
            } catch {
                throw MediaExportError.webcamUnavailable
            }
        } else if snapshot.effects.webcam.isEnabled {
            throw MediaExportError.webcamUnavailable
        }
        let clicks = snapshot.effects.events.filter { $0.kind == .click }
        if snapshot.effects.clickSound != "off", !clicks.isEmpty {
            try clickWAV(named: snapshot.effects.clickSound).write(to: clickURL, options: .atomic)
            let clickAsset = AVURLAsset(url: clickURL)
            if let clickSource = try await clickAsset.loadTracks(withMediaType: .audio).first,
               let clickTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let clickDuration = try await clickAsset.load(.duration)
                let timing = MediaOutputTiming(freezeFrame: snapshot.effects.freezeFrame)
                for click in clicks {
                    let at = CMTime(seconds: Double(timing.outputTimeMicroseconds(forSourceTime: click.timeMicroseconds)) / 1_000_000, preferredTimescale: 600)
                    if at < duration { try clickTrack.insertTimeRange(.init(start: .zero, duration: clickDuration), of: clickSource, at: at) }
                }
            }
        }
        return composition
    }

    private nonisolated static func clickWAV(named sound: String) -> Data {
        let sampleRate = 44_100
        let count = sampleRate / 25
        let frequency: Double = sound == "pebble_tap" ? 720 : sound == "latch_tap" ? 1_080 : sound == "wisp_puff" ? 420 : 860
        var pcm = Data(capacity: count * 2)
        for index in 0..<count {
            let envelope = pow(1 - Double(index) / Double(count), 3)
            var sample = Int16((sin(2 * .pi * frequency * Double(index) / Double(sampleRate)) * envelope * 14_000).rounded()).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        var data = Data("RIFF".utf8)
        func append(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        append(UInt32(36 + pcm.count)); data.append(Data("WAVEfmt ".utf8)); append(16); append16(1); append16(1)
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append16(2); append16(16)
        data.append(Data("data".utf8)); append(UInt32(pcm.count)); data.append(pcm)
        return data
    }

    private static func outputCodec(at url: URL) async throws -> MediaExportCodec? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
              let description = try await track.load(.formatDescriptions).first else { return nil }
        switch CMFormatDescriptionGetMediaSubType(description) {
        case kCMVideoCodecType_H264: return MediaExportCodec.h264
        case kCMVideoCodecType_HEVC: return MediaExportCodec.hevc
        default: return nil
        }
    }
}
