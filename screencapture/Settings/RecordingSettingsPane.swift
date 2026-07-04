import SwiftUI

struct RecordingSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SettingsSectionCard("Format & Constraints") {
                    Picker("Video format", selection: Binding(
                        get: { settings.recordingFormat },
                        set: { settings.recordingFormat = $0 })) {
                        ForEach(RecordingFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .font(.system(size: 12))
                    .controlSize(.small)
                    
                    if settings.recordingFormat == .gif {
                        Divider().padding(.vertical, 2)
                        
                        HStack {
                            Text("GIF frame rate (FPS)")
                                .font(.system(size: 12))
                            Spacer()
                            Stepper("", value: $settings.gifFPS, in: 5...20)
                                .controlSize(.small)
                            Text("\(settings.gifFPS) fps")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                        
                        HStack {
                            Text("Maximum frames limit")
                                .font(.system(size: 12))
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
                    Toggle("Record system audio playback (MP4 only)", isOn: $settings.recordSystemAudio)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Toggle("Highlight mouse clicks with visual ripple", isOn: $settings.highlightClicksDuringRecording)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                SettingsSectionCard("Scrolling Capture") {
                    Toggle("Enable auto-scroll trigger by default", isOn: $settings.scrollingAutoScroll)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider().padding(.vertical, 2)
                    
                    HStack {
                        Text("Auto-scroll pixels step distance")
                            .font(.system(size: 12))
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
