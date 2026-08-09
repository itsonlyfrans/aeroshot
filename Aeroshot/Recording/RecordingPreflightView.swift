import Combine

@MainActor
final class RecordingPreflightModel: ObservableObject {
    let configuration: RecordingSessionConfiguration
    @Published private(set) var readiness: RecordingPreflightReadiness

    init(configuration: RecordingSessionConfiguration, readiness: RecordingPreflightReadiness) {
        self.configuration = configuration
        self.readiness = readiness
    }

    var blockingMessage: String? {
        if readiness.permissionStatuses[.screenRecording] != .granted {
            return "Screen Recording permission is required."
        }
        if configuration.audio.microphoneDeviceID != nil,
           readiness.permissionStatuses[.microphone] != .granted {
            return "Microphone permission is required for this recording."
        }
        if configuration.webcam != nil, readiness.permissionStatuses[.camera] != .granted {
            return "Camera permission is required for the webcam overlay."
        }
        if readiness.availableSpaceBytes < configuration.requiredSpaceEstimateBytes {
            return "Not enough free space to start recording."
        }
        return nil
    }

    var isReady: Bool { blockingMessage == nil }
}
