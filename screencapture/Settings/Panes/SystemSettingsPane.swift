import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let settingsProfileDidChange = Notification.Name("settingsProfileDidChange")
}

struct SystemSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var appState: AppState
    @State private var advancedExpanded = false
    @State private var refreshToken = UUID()
    @State private var profileAlert: ProfileAlert?

    private enum ProfileAlert: Identifiable {
        case resetConfirm
        case importFailed(String)

        var id: String {
            switch self {
            case .resetConfirm: return "reset"
            case .importFailed(let message): return "import-\(message)"
            }
        }
    }

    var body: some View {
        SettingsPaneLayout {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                appHero

                if !SettingsPermissions.allGranted {
                    SettingsInlineCallout(
                        symbol: "exclamationmark.shield.fill",
                        message: "\(SettingsPermissions.healthLabel). Grant missing access for full functionality.",
                        buttonTitle: "Open System Settings"
                    ) {
                        openScreenRecordingSettings()
                    }
                }

                SettingsPanel("Permissions") {
                    SettingsPermissionTile(
                        title: "Screen Recording",
                        description: "Required to capture windows, areas, and video.",
                        granted: SettingsPermissions.screenRecordingGranted,
                        openSettings: openScreenRecordingSettings
                    )

                    Divider().opacity(0.5)

                    SettingsPermissionTile(
                        title: "Input Monitoring",
                        description: "Required for global keyboard shortcuts.",
                        granted: SettingsPermissions.inputMonitoringGranted,
                        openSettings: { HotkeyManager.openInputMonitoringSettings() }
                    )

                    Divider().opacity(0.5)

                    SettingsPermissionTile(
                        title: "Accessibility",
                        description: "Required for automatic scrolling captures.",
                        granted: SettingsPermissions.accessibilityGranted,
                        openSettings: { ScrollEventPoster.openAccessibilitySettings() }
                    )

                    Divider().opacity(0.5)

                    Button {
                        appState.showPermissionWizard()
                    } label: {
                        Label("Open setup guide", systemImage: "sparkles")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, SettingsTheme.spacingXS)
                }
                .id(refreshToken)

                SettingsExpandablePanel(
                    "Advanced",
                    subtitle: "Power-user options and app identity",
                    isExpanded: $advancedExpanded
                ) {
                    SettingsToggle(
                        title: "Add OCR captures to history",
                        subtitle: "Save plain text OCR results as searchable .txt files",
                        isOn: $settings.addOCRCapturesToHistory,
                        symbol: "text.viewfinder"
                    )

                    HStack(spacing: SettingsTheme.spacingS) {
                        Image(systemName: "dock.rectangle")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dock icon")
                                .font(.headline)
                            Text("Hidden — ScreenCapture runs as a menu bar accessory.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.top, SettingsTheme.spacingS)

                    Divider().opacity(0.5)

                    VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                        Text("Settings profile")
                            .font(.headline)
                        Text("Export your preferences to share with teammates or back up before experimenting.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: SettingsTheme.spacingM) {
                            Button("Export profile…") { exportProfile() }
                            Button("Import profile…") { importProfile() }
                            Button("Reset all to defaults") { profileAlert = .resetConfirm }
                                .foregroundStyle(.red)
                        }
                        .controlSize(.regular)
                    }
                    .padding(.top, SettingsTheme.spacingXS)
                }
            }
        }
        .alert(item: $profileAlert) { alert in
            switch alert {
            case .resetConfirm:
                Alert(
                    title: Text("Reset all settings?"),
                    message: Text("This restores every preference and keyboard shortcut to factory defaults."),
                    primaryButton: .destructive(Text("Reset")) {
                        settings.resetAllToDefaults()
                        NotificationCenter.default.post(name: .settingsProfileDidChange, object: nil)
                    },
                    secondaryButton: .cancel()
                )
            case .importFailed(let message):
                Alert(
                    title: Text("Import failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .onAppear { refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private var appHero: some View {
        HStack(spacing: SettingsTheme.spacingL) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
            }

            VStack(alignment: .leading, spacing: SettingsTheme.spacingXS) {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ScreenCapture")
                    .font(.title2.bold())
                Text("Version \(versionString)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("© \(Calendar.current.component(.year, from: Date())) ScreenCapture")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: SettingsTheme.spacingXS) {
                Text(SettingsPermissions.healthLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SettingsPermissions.allGranted ? Color.green : Color.orange)
                    .padding(.horizontal, SettingsTheme.spacingS)
                    .padding(.vertical, SettingsTheme.spacingXS)
                    .background(
                        (SettingsPermissions.allGranted ? Color.green : Color.orange).opacity(0.12),
                        in: Capsule()
                    )
                Text("Permissions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, SettingsTheme.spacingS)
    }

    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func refreshPermissions() {
        refreshToken = UUID()
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func exportProfile() {
        guard let data = settings.exportProfile() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ScreenCapture-Profile.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                try settings.importProfile(from: data)
                NotificationCenter.default.post(name: .settingsProfileDidChange, object: nil)
            } catch {
                profileAlert = .importFailed(error.localizedDescription)
            }
        }
    }
}
