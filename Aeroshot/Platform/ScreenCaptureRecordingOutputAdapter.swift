import AVFoundation
import Foundation
import ScreenCaptureKit

/// The only deployment-target-facing type that names `SCRecordingOutput`.
/// Callers must cross the macOS 15 availability check before constructing it.
@available(macOS 15.0, *)
enum ScreenCaptureRecordingOutputAdapter {
    static func makeOutput(
        url: URL,
        delegate: any SCRecordingOutputDelegate,
        videoCodec: AVVideoCodecType = .h264,
        fileType: AVFileType = .mp4
    ) -> SCRecordingOutput {
        let configuration = SCRecordingOutputConfiguration()
        configuration.outputURL = url
        configuration.videoCodecType = videoCodec
        configuration.outputFileType = fileType
        return SCRecordingOutput(configuration: configuration, delegate: delegate)
    }

    static func add(_ output: SCRecordingOutput, to stream: SCStream) throws {
        try stream.addRecordingOutput(output)
    }

    static func remove(_ output: SCRecordingOutput, from stream: SCStream) throws {
        try stream.removeRecordingOutput(output)
    }
}
