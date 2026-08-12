import Foundation
import Testing
@testable import Aeroshot

struct HUDToolbarModelTests {
    @MainActor
    @Test func savedLocationUsesTheActualOutputFolder() {
        let model = HUDToolbarModel(
            selected: .area,
            options: HUDRecordingOptions(
                microphoneEnabled: false,
                systemAudioEnabled: false,
                cameraEnabled: false,
                countdownSeconds: 0
            )
        )

        model.showSaved(url: URL(fileURLWithPath: "/tmp/Custom Captures/movie.mp4"), duration: "0:03")

        #expect(model.savedLocationName == "Custom Captures")
    }

    @MainActor
    @Test func recordingControlsPersistOneCoherentRequest() {
        let model = HUDToolbarModel(
            selected: .area,
            options: HUDRecordingOptions(
                microphoneEnabled: false,
                systemAudioEnabled: true,
                cameraEnabled: false,
                countdownSeconds: 3
            )
        )
        var request: (CaptureIntent, HUDRecordingOptions)?
        model.onRecord = { request = ($0, $1) }

        model.toggleMicrophone()
        model.toggleCamera()
        model.cycleCountdown()
        model.select(.ocr)
        model.startRecording(.window)

        #expect(model.selected == .ocr)
        #expect(request?.0 == .window)
        #expect(request?.1 == HUDRecordingOptions(
            microphoneEnabled: true,
            systemAudioEnabled: true,
            cameraEnabled: true,
            countdownSeconds: 5
        ))
    }

    @MainActor
    @Test func deniedMicrophonePermissionLeavesTheOptionOff() async {
        let model = HUDToolbarModel(
            selected: .area,
            options: HUDRecordingOptions(
                microphoneEnabled: false,
                systemAudioEnabled: false,
                cameraEnabled: false,
                countdownSeconds: 3
            ),
            reviewSelection: true
        )
        var requests = 0
        var persistedChanges = 0
        model.onRequestMicrophonePermission = {
            requests += 1
            return false
        }
        model.onOptionsChanged = { _ in persistedChanges += 1 }

        model.toggleMicrophone()
        while model.isRequestingMicrophonePermission {
            await Task.yield()
        }

        #expect(requests == 1)
        #expect(!model.options.microphoneEnabled)
        #expect(persistedChanges == 0)
    }

    @MainActor
    @Test func gifDoesNotRequestOrEnableUnsupportedAudioControls() {
        let model = HUDToolbarModel(
            selected: .area,
            options: HUDRecordingOptions(
                microphoneEnabled: false,
                systemAudioEnabled: false,
                cameraEnabled: false,
                countdownSeconds: 3
            ),
            recordingFormat: .gif
        )
        var microphoneRequests = 0
        model.onRequestMicrophonePermission = {
            microphoneRequests += 1
            return true
        }

        model.toggleMicrophone()
        model.toggleSystemAudio()

        #expect(!model.supportsAudioAndPause)
        #expect(microphoneRequests == 0)
        #expect(!model.options.microphoneEnabled)
        #expect(!model.options.systemAudioEnabled)
    }
}
