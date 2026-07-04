import AppKit
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("After Capture") {
                Toggle("Copy to clipboard", isOn: $settings.copyToClipboardAfterCapture)
                Toggle("Save to disk", isOn: $settings.saveToDiskAfterCapture)
                Toggle("Show floating thumbnail", isOn: $settings.showThumbnailAfterCapture)
                Toggle("Play sound", isOn: $settings.playCaptureSound)
                HStack {
                    Text("Thumbnail duration")
                    Slider(value: $settings.thumbnailDuration, in: 2...15)
                    Text("\(Int(settings.thumbnailDuration))s").monospacedDigit()
                }
            }
            Section("Files") {
                HStack {
                    Text("Save to:")
                    Text(settings.saveDirectoryPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { chooseFolder() }
                }
                Picker("Format", selection: Binding(
                    get: { settings.imageFormat },
                    set: { settings.imageFormat = $0 })) {
                    ForEach(ImageFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                if settings.imageFormat != .png {
                    HStack {
                        Text("Quality")
                        Slider(value: $settings.jpegQuality, in: 0.3...1.0)
                        Text(String(format: "%.0f%%", settings.jpegQuality * 100)).monospacedDigit()
                    }
                }
                Toggle("Downscale retina captures to 1x", isOn: $settings.downscaleRetina)
            }
        }
        .formStyle(.grouped)
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
