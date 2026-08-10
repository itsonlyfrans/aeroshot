import AVFoundation
import Foundation
import Testing
@testable import Aeroshot

struct ScreenRecordingServiceTests {
    @Test func preparesEachEnabledAudioInputBeforeWriting() throws {
        for setup in [
            (systemAudio: false, microphone: false),
            (systemAudio: false, microphone: true),
            (systemAudio: true, microphone: false),
            (systemAudio: true, microphone: true),
        ] {
            let url = FileManager.default.temporaryDirectory.appending(path: "recording-inputs-\(UUID()).mp4")
            defer { try? FileManager.default.removeItem(at: url) }
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            var prepared: (AVAssetWriterInput?, AVAssetWriterInput?) = (nil, nil)

            try ScreenRecordingService.prepareAudioInputs(
                for: writer,
                includeSystemAudio: setup.systemAudio,
                includeMicrophone: setup.microphone,
                assign: { prepared = ($0, $1) }
            )

            #expect((prepared.0 != nil) == setup.systemAudio)
            #expect((prepared.1 != nil) == setup.microphone)
            let inputCount = writer.inputs.count
            #expect(inputCount == (setup.systemAudio ? 1 : 0) + (setup.microphone ? 1 : 0))
            #expect(writer.startWriting())
            #expect(writer.inputs.count == inputCount)
            writer.cancelWriting()
        }
    }
}
