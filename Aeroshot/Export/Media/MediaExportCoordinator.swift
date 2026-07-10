@preconcurrency import AVFoundation
import Foundation

nonisolated enum MediaExportError: Error, Equatable, Sendable {
    case missingSourceAsset
    case invalidSourcePath
    case sourceUnavailable
    case sourceHasNoVideo
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

        let asset = AVURLAsset(url: snapshot.sourceURL)
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
        let partial = destination.deletingLastPathComponent()
            .appending(path: ".(destination.lastPathComponent).(UUID().uuidString).partial.mp4")
        try? FileManager.default.removeItem(at: partial)
        defer { try? FileManager.default.removeItem(at: partial) }

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
