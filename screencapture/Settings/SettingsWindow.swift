import AppKit
import SwiftUI

struct SettingsWindow: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            HotkeySettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 480)
        .padding(.bottom, 8)
    }
}

struct GeneralSettingsTab: View {
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
        .padding()
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

struct HotkeySettingsTab: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var hotkeys: [HotkeyAction: Hotkey] = [:]

    var body: some View {
        Form {
            ForEach(HotkeyAction.allCases) { action in
                HStack {
                    Text(action.displayName)
                    Spacer()
                    HotkeyRecorderView(
                        action: action,
                        hotkey: Binding(
                            get: { hotkeys[action] ?? action.defaultHotkey },
                            set: { hotkeys[action] = $0 }
                        ),
                        onChange: { new in
                            settings.setHotkey(new, for: action)
                            if let delegate = NSApp.delegate as? AppDelegate {
                                delegate.rebindHotkeys()
                            }
                        }
                    )
                    .frame(width: 140, height: 24)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            HotkeyManager.requestInputMonitoringAccess()
            HotkeyManager.shared.refreshMonitors()
            hotkeys = settings.hotkeys()
        }
        .safeAreaInset(edge: .bottom) {
            if !HotkeyManager.hasInputMonitoringAccess {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Enable Input Monitoring in System Settings for background shortcuts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open…") { HotkeyManager.openInputMonitoringSettings() }
                        .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .toolbar {
            Button("Reset to Defaults") {
                settings.resetHotkeysToDefaults()
                hotkeys = settings.hotkeys()
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.rebindHotkeys()
                }
            }
        }
    }
}
