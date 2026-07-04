import AppKit
import SwiftUI



struct GeneralSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SettingsSectionCard("After Capture") {
                    SettingsToggleRow(title: "Copy to clipboard", subtitle: "Copy captured image to pasteboard automatically", isOn: $settings.copyToClipboardAfterCapture)
                    
                    Divider().padding(.vertical, 2)
                    
                    SettingsToggleRow(title: "Save to disk", subtitle: "Save captures automatically to target folder", isOn: $settings.saveToDiskAfterCapture)
                    
                    Divider().padding(.vertical, 2)
                    
                    SettingsToggleRow(title: "Quick-access thumbnail", subtitle: "Show overlay quick-access thumbnail at corner", isOn: $settings.showThumbnailAfterCapture)
                    
                    Divider().padding(.vertical, 2)
                    
                    SettingsToggleRow(title: "Play capture sound", subtitle: "Play sound effect when taking a screenshot", isOn: $settings.playCaptureSound)
                    
                    Divider().padding(.vertical, 2)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Thumbnail duration")
                                .font(.system(size: 12, weight: .medium))
                            Text("Auto-dismiss timer for quick-access thumbnail")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Slider(value: $settings.thumbnailDuration, in: 2...15)
                            .frame(width: 120)
                            .controlSize(.small)
                        Text("\(Int(settings.thumbnailDuration))s")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
                
                SettingsSectionCard("Files & Format") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save screenshots to")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Spacer()
                        Text(settings.saveDirectoryPath)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                            .frame(maxWidth: 200)
                        Button("Choose…") { chooseFolder() }
                            .controlSize(.small)
                    }
                    
                    Divider().padding(.vertical, 2)
                    
                    HStack {
                        Text("Default image format")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.imageFormat },
                            set: { settings.imageFormat = $0 })) {
                            ForEach(ImageFormat.allCases) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                        .controlSize(.small)
                    }
                    
                    if settings.imageFormat != .png {
                        Divider().padding(.vertical, 2)
                        
                        HStack {
                            Text("JPEG compression quality")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Slider(value: $settings.jpegQuality, in: 0.3...1.0)
                                .frame(width: 120)
                                .controlSize(.small)
                            Text(String(format: "%.0f%%", settings.jpegQuality * 100))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    
                    Divider().padding(.vertical, 2)
                    
                    SettingsToggleRow(title: "Downscale Retina captures", subtitle: "Export screenshots at 1x resolution", isOn: $settings.downscaleRetina)
                }
            }
            .padding(18)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectoryPath = url.path
        }
    }
}
