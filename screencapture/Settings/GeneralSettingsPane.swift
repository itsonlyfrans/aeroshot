import AppKit
import SwiftUI

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.85))
                .padding(.horizontal, 4)
            
            VStack(spacing: 10) {
                content
            }
            .padding(14)
            .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .padding(.bottom, 12)
    }
}

struct GeneralSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SettingsSectionCard("After Capture") {
                    Toggle("Copy to clipboard after capture", isOn: $settings.copyToClipboardAfterCapture)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Toggle("Save to disk after capture", isOn: $settings.saveToDiskAfterCapture)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Toggle("Show floating quick-access thumbnail", isOn: $settings.showThumbnailAfterCapture)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Toggle("Play capture pop sound effect", isOn: $settings.playCaptureSound)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider().padding(.vertical, 2)
                    
                    HStack {
                        Text("Thumbnail auto-dismiss duration")
                            .font(.system(size: 12))
                        Spacer()
                        Slider(value: $settings.thumbnailDuration, in: 2...15)
                            .frame(width: 140)
                            .controlSize(.small)
                        Text("\(Int(settings.thumbnailDuration))s")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
                
                SettingsSectionCard("Files & Format") {
                    HStack {
                        Text("Save screenshots to:")
                            .font(.system(size: 12))
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
                            .frame(maxWidth: 240)
                        Button("Choose…") { chooseFolder() }
                            .controlSize(.small)
                    }
                    
                    Divider().padding(.vertical, 2)
                    
                    Picker("Default image format", selection: Binding(
                        get: { settings.imageFormat },
                        set: { settings.imageFormat = $0 })) {
                        ForEach(ImageFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .font(.system(size: 12))
                    .controlSize(.small)
                    
                    if settings.imageFormat != .png {
                        HStack {
                            Text("JPEG quality compression")
                                .font(.system(size: 12))
                            Spacer()
                            Slider(value: $settings.jpegQuality, in: 0.3...1.0)
                                .frame(width: 140)
                                .controlSize(.small)
                            Text(String(format: "%.0f%%", settings.jpegQuality * 100))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    
                    Toggle("Downscale Retina (high-res) captures to 1x", isOn: $settings.downscaleRetina)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
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
