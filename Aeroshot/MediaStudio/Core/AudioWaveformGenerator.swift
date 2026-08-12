@preconcurrency import AVFoundation
import Foundation

nonisolated enum AudioWaveformError: Error, Equatable {
    case missingAudio, cannotRead
}

/// Produces a bounded peak envelope for Studio display without retaining decoded audio.
nonisolated struct AudioWaveformGenerator: Sendable {
    func samples(from url: URL, sampleCount: Int) async throws -> [Float] {
        try await samples(from: AVURLAsset(url: url), sampleCount: sampleCount)
    }

    func samples(from asset: AVAsset, sampleCount: Int) async throws -> [Float] {
        guard sampleCount > 0 else { return [] }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw AudioWaveformError.missingAudio }
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration > .zero else { throw AudioWaveformError.cannotRead }
        let durationSeconds = duration.seconds
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
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
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer),
                  let format = CMSampleBufferGetFormatDescription(buffer),
                  let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  stream.mSampleRate > 0, stream.mChannelsPerFrame > 0 else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            guard byteCount > 0 else { continue }
            var bytes = Data(count: byteCount)
            let status = bytes.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: raw.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw AudioWaveformError.cannotRead }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard presentationTime.isFinite else { throw AudioWaveformError.cannotRead }
            bytes.withUnsafeBytes { raw in
                let values = raw.bindMemory(to: Float.self)
                let channelCount = Int(stream.mChannelsPerFrame)
                let frameCount = min(CMSampleBufferGetNumSamples(buffer), values.count / channelCount)
                for frame in 0..<frameCount {
                    let seconds = max(0, presentationTime + Double(frame) / stream.mSampleRate)
                    let bucket = min(sampleCount - 1, Int(seconds / durationSeconds * Double(sampleCount)))
                    let offset = frame * channelCount
                    for channel in 0..<channelCount {
                        let value = values[offset + channel]
                        peaks[bucket] = max(peaks[bucket], value.isFinite ? abs(value) : 0)
                    }
                }
            }
        }
        guard reader.status == .completed else { throw AudioWaveformError.cannotRead }
        let maximum = peaks.max() ?? 0
        return maximum > 0 ? peaks.map { min(1, $0 / maximum) } : peaks
    }
}
