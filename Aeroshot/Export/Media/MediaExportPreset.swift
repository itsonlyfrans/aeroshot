import AVFoundation
import Foundation

nonisolated enum MediaExportCodec: String, Sendable { case h264, hevc }

nonisolated struct MediaExportPreset: Equatable, Sendable {
    let codec: MediaExportCodec
    let pixelSize: AeroPixelSize
    let frameRate: AeroMediaTime
    let targetBitRate: Int

    static func h264(size: AeroPixelSize, frameRate: AeroMediaTime) -> Self {
        Self(codec: .h264, pixelSize: size, frameRate: frameRate, targetBitRate: bitRate(size: size, fps: fps(frameRate), factor: 0.075))
    }

    static func hevc(size: AeroPixelSize, frameRate: AeroMediaTime) -> Self {
        Self(codec: .hevc, pixelSize: size, frameRate: frameRate, targetBitRate: bitRate(size: size, fps: fps(frameRate), factor: 0.045))
    }

    func validate() throws {
        guard pixelSize.width.isMultiple(of: 2), pixelSize.height.isMultiple(of: 2),
              (16...8_192).contains(pixelSize.width), (16...8_192).contains(pixelSize.height) else {
            throw MediaExportError.invalidResolution
        }
        let rate = Self.fps(frameRate)
        guard rate >= 1, rate <= 120 else { throw MediaExportError.invalidFrameRate }
    }

    func estimatedSize(durationSeconds: Double, audioBitRate: Int = 192_000) -> MediaExportSizeEstimate {
        let bytes = Int64(ceil(max(durationSeconds, 0) * Double(targetBitRate + audioBitRate) / 8))
        return MediaExportSizeEstimate(bytes: bytes, uncertaintyFraction: 0.25)
    }

    var avPresetName: String {
        switch codec {
        case .h264: AVAssetExportPresetHighestQuality
        case .hevc: AVAssetExportPresetHEVCHighestQuality
        }
    }

    private static func fps(_ value: AeroMediaTime) -> Double { Double(value.value) / Double(value.timescale) }
    private static func bitRate(size: AeroPixelSize, fps: Double, factor: Double) -> Int {
        max(500_000, Int(Double(size.width * size.height) * fps * factor))
    }
}

nonisolated struct MediaExportSizeEstimate: Equatable, Sendable {
    let bytes: Int64
    /// VBR output and source complexity commonly move final size. The estimate
    /// is intentionally presented as ±25%, not false precision.
    let uncertaintyFraction: Double
}

nonisolated enum MediaExportColorPolicy: String, Sendable {
    /// Current export normalizes SDR output to Rec.709. HDR and Display-P3
    /// preservation require an explicitly color-managed compositor.
    case rec709SDR
}
