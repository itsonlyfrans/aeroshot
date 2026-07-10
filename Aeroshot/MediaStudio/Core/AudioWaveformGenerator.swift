@preconcurrency import AVFoundation
import Foundation

nonisolated enum AudioWaveformError: Error, Equatable {
    case missingAudio, cannotRead
}

/// Produces a bounded peak envelope for Studio display without retaining decoded audio.
struct AudioWaveformGenerator: Sendable {
    func samples(from url: URL, sampleCount: Int) async throws -> [Float] {
        guard sampleCount > 0 else { return [] }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioWaveformError.missingAudio
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioWaveformError.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw AudioWaveformError.cannotRead }

        var peaks = Array(repeating: Float.zero, count: sampleCount)
        var sampleIndex = 0
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            guard byteCount > 0 else { continue }
            var bytes = Data(count: byteCount)
            let status = bytes.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: raw.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw AudioWaveformError.cannotRead }
            bytes.withUnsafeBytes { raw in
                let values = raw.bindMemory(to: Float.self)
                for value in values {
                    let bucket = min(sampleCount - 1, sampleIndex % sampleCount)
                    peaks[bucket] = max(peaks[bucket], abs(value.isFinite ? value : 0))
                    sampleIndex += 1
                }
            }
        }
        guard reader.status == .completed else { throw AudioWaveformError.cannotRead }
        let maximum = peaks.max() ?? 0
        return maximum > 0 ? peaks.map { min(1, $0 / maximum) } : peaks
    }
}
