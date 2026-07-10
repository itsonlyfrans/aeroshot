import AVFoundation
import SwiftUI

struct RecordingSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var gifAdvancedExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPaneLayout(pane: .recording) {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                SettingsHeroHeader(
                    "Recording",
                    symbol: "record.circle",
                    subtitle: "Configure screen recordings and animated GIF exports.",
                    chips: [
                        settings.recordingFormat.displayName,
                        settings.recordSystemAudio ? "System audio" : "Video only"
                    ]
                )

                SettingsPanel("Format", symbol: "film") {
                    HStack(spacing: SettingsTheme.spacingM) {
                        ForEach(RecordingFormat.allCases) { format in
                            SettingsSelectionCard(
                                title: format.displayName,
                                subtitle: format == .mp4
                                    ? "High quality video with optional audio"
                                    : "Lightweight animated image",
                                symbol: format == .mp4 ? "film" : "photo.stack",
                                isSelected: settings.recordingFormat == format
                            ) {
                                withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                                    settings.recordingFormat = format
                                }
                                SettingsTheme.performHaptic()
                            }
                        }
                    }
                }

                SettingsPanel("Options", symbol: "slider.horizontal.3") {
                    SettingsToggle(
                        title: "Record system audio",
                        subtitle: "Capture audio playback (MP4 only)",
                        isOn: $settings.recordSystemAudio,
                        symbol: "speaker.wave.3"
                    )

                    SettingsToggle(
                        title: "Highlight clicks",
                        subtitle: "Show a visual ripple on mouse clicks",
                        isOn: $settings.highlightClicksDuringRecording,
                        symbol: "cursorarrow.rays"
                    )

                    SettingsToggle(
                        title: "Add recordings to history",
                        subtitle: "Keep MP4 and GIF files in the history browser",
                        isOn: $settings.addRecordingsToHistory,
                        symbol: "clock.arrow.circlepath"
                    )

                    SettingsToggle(
                        title: "Record microphone",
                        subtitle: "Include your voice in MP4 recordings",
                        isOn: $settings.recordMicrophone,
                        symbol: "mic.fill"
                    )

                    if settings.recordMicrophone {
                        Picker("Microphone", selection: $settings.recordingMicrophoneDeviceID) {
                            Text("System Default").tag("")
                            ForEach(Self.microphones, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID)
                            }
                        }
                        .accessibilityLabel("Recording microphone")
                    }

                    SettingsToggle(
                        title: "Webcam overlay",
                        subtitle: "Show a draggable picture-in-picture bubble while recording",
                        isOn: $settings.showWebcamOverlay,
                        symbol: "person.crop.circle"
                    )
                }

                if settings.recordingFormat == .gif {
                    SettingsExpandablePanel(
                        "Advanced GIF options",
                        subtitle: "Frame rate and length limits",
                        isExpanded: $gifAdvancedExpanded
                    ) {
                        SettingsValueSlider(
                            title: "Frame rate",
                            value: Binding(
                                get: { Double(settings.gifFPS) },
                                set: { settings.gifFPS = Int($0) }
                            ),
                            in: 5...20,
                            step: 1,
                            valueLabel: { "\(Int($0)) fps" }
                        )

                        SettingsValueSlider(
                            title: "Maximum frames",
                            value: Binding(
                                get: { Double(settings.gifMaxFrames) },
                                set: { settings.gifMaxFrames = Int($0) }
                            ),
                            in: 60...600,
                            step: 30,
                            valueLabel: { "\(Int($0))" }
                        )
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                SettingsFootnoteSection("Related") {
                    SettingsQuickLink(
                        title: "Scrolling capture",
                        subtitle: "Long-page stitch settings",
                        pane: .scrolling
                    )
                }
            }
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: settings.recordingFormat)
        }
    }

    private static var microphones: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
    }
}
