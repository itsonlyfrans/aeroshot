import SwiftUI
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

struct RecordingPreflightView: View {
    @ObservedObject var model: RecordingPreflightModel

    var body: some View {
        Form {
            LabeledContent("Source", value: sourceDescription)
            LabeledContent("Resolution", value: "\(model.configuration.dimensions.width) × \(model.configuration.dimensions.height)")
            LabeledContent("Frame rate", value: "\(model.configuration.frameRate.framesPerSecond) fps")
            LabeledContent("Cursor", value: model.configuration.cursorMode == .hidden ? "Hidden" : "Visible")
            LabeledContent("System audio", value: model.configuration.audio.capturesSystemAudio ? "On" : "Off")
            LabeledContent("Microphone", value: model.configuration.audio.microphoneDeviceID == nil ? "Off" : "On")
            LabeledContent("Webcam", value: model.configuration.webcam == nil ? "Off" : "On")
            LabeledContent("Countdown", value: "\(model.configuration.countdown.seconds)s")
            if let message = model.blockingMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } else {
                Label("Ready to record", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private var sourceDescription: String {
        switch model.configuration.source {
        case .display: "Display"
        case .window: "Window"
        case .region: "Selected region"
        }
    }
}
