import SwiftUI

struct RecordingSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SettingsSectionCard("Format & Constraints") {
                    HStack {
                        Text("Video format")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.recordingFormat },
                            set: { settings.recordingFormat = $0 })) {
                            ForEach(RecordingFormat.allCases) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        .controlSize(.small)
                    }
                    
                    if settings.recordingFormat == .gif {
                        Divider().padding(.vertical, 2)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("GIF frame rate (FPS)")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Spacer()
                            Stepper("", value: $settings.gifFPS, in: 5...20)
                                .controlSize(.small)
                            Text("\(settings.gifFPS) fps")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Maximum frames limit")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Spacer()
                            Stepper("", value: $settings.gifMaxFrames, in: 60...600, step: 30)
                                .controlSize(.small)
                            Text("\(settings.gifMaxFrames)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
                
                SettingsSectionCard("Options") {
                    SettingsToggleRow(title: "Record system audio", subtitle: "Capture system audio playback (MP4 only)", isOn: $settings.recordSystemAudio)
                    
                    Divider().padding(.vertical, 2)
                    
                    SettingsToggleRow(title: "Highlight clicks", subtitle: "Show a visual ripple effect on mouse clicks", isOn: $settings.highlightClicksDuringRecording)
                }
                
                SettingsSectionCard("Scrolling Capture") {
                    SettingsToggleRow(title: "Auto-scroll trigger", subtitle: "Trigger auto-scroll by default in scrolling mode", isOn: $settings.scrollingAutoScroll)
                    
                    Divider().padding(.vertical, 2)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-scroll speed step")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Spacer()
                        Stepper("", value: $settings.scrollingAutoScrollPixels, in: 40...400, step: 20)
                            .controlSize(.small)
                        Text("\(settings.scrollingAutoScrollPixels) px")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                    
                    if !ScrollEventPoster.hasAccessibilityAccess {
                        Divider().padding(.vertical, 2)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 11))
                            Text("Requires Accessibility permission for auto-scroll.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Grant Access…") { ScrollEventPoster.openAccessibilitySettings() }
                                .controlSize(.small)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.2), lineWidth: 0.5))
                    }
                }
            }
            .padding(18)
        }
    }
}
