import SwiftUI

struct RecordingSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Format") {
                Picker("Recording format", selection: Binding(
                    get: { settings.recordingFormat },
                    set: { settings.recordingFormat = $0 })) {
                    ForEach(RecordingFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                if settings.recordingFormat == .gif {
                    Stepper("GIF frame rate: \(settings.gifFPS) fps",
                            value: $settings.gifFPS, in: 5...20)
                    Stepper("Max frames: \(settings.gifMaxFrames)",
                            value: $settings.gifMaxFrames, in: 60...600, step: 30)
                }
            }
            Section("Options") {
                Toggle("Record system audio (MP4 only)", isOn: $settings.recordSystemAudio)
                Toggle("Highlight clicks during recording", isOn: $settings.highlightClicksDuringRecording)
            }
            Section("Scrolling Capture") {
                Toggle("Auto-scroll by default", isOn: $settings.scrollingAutoScroll)
                Stepper("Scroll step: \(settings.scrollingAutoScrollPixels) px",
                        value: $settings.scrollingAutoScrollPixels, in: 40...400, step: 20)
                if !ScrollEventPoster.hasAccessibilityAccess {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Auto-scroll requires Accessibility permission.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open…") { ScrollEventPoster.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
