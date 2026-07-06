import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let settingsProfileDidChange = Notification.Name("settingsProfileDidChange")
    static let appPresenceDidChange = Notification.Name("appPresenceDidChange")
}

struct SystemSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var appState: AppState
    @State private var advancedExpanded = false
    @State private var permissionRefreshTick = 0
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
                        if !SettingsPermissions.screenRecordingGranted {
                            SettingsPermissions.requestScreenRecording()
                        } else {
                            SettingsPermissions.requestAccessibility()
                        }
                    }
                }

                SettingsPanel("Permissions") {
                    SettingsPermissionTile(
                        title: "Screen Recording",
                        description: "Required to capture windows, areas, and video.",
                        granted: SettingsPermissions.screenRecordingGranted,
                        openSettings: { SettingsPermissions.requestScreenRecording() }
                    )

                    Divider().opacity(0.5)

                    SettingsPermissionTile(
                        title: "Accessibility",
                        description: "Required for global shortcuts, click highlights, and scrolling auto-scroll.",
                        granted: SettingsPermissions.accessibilityGranted,
                        openSettings: { SettingsPermissions.requestAccessibility() }
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
                .id(permissionRefreshTick)

                SettingsPanel("App presence") {
                    SettingsToggle(
                        title: "Show in menu bar",
                        subtitle: "Camera icon with capture menu in the top-right of the screen",
                        isOn: $settings.showInMenuBar,
                        symbol: "menubar.rectangle"
                    )
                    .onChange(of: settings.showInMenuBar) { _, _ in
                        scheduleAppPresenceChange()
                    }

                    SettingsToggle(
                        title: "Show in Dock",
                        subtitle: "Keep an app icon in the Dock for quick access",
                        isOn: $settings.showInDock,
                        symbol: "dock.rectangle"
                    )
                    .onChange(of: settings.showInDock) { _, _ in
                        scheduleAppPresenceChange()
                    }

                    if settings.runsHeadless {
                        HStack(alignment: .top, spacing: SettingsTheme.spacingS) {
                            Image(systemName: "eye.slash")
                                .foregroundStyle(.orange)
                                .font(.system(size: 13, weight: .semibold))
                            Text("Background mode — use keyboard shortcuts, Shortcuts, or AppleScript. Reopen the app to reach Settings.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(SettingsTheme.spacingM)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5)
                        }
                    } else {
                        Text("Current mode: \(settings.appPresenceSummary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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
            schedulePermissionRefresh()
        }
    }

    private func scheduleAppPresenceChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .appPresenceDidChange, object: nil)
        }
    }

    private func schedulePermissionRefresh() {
        DispatchQueue.main.async {
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
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Aeroshot")
                    .font(.title2.bold())
                Text("Version \(versionString)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("© \(Calendar.current.component(.year, from: Date())) Aeroshot")
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
        permissionRefreshTick += 1
    }

    private func openScreenRecordingSettings() {
        SettingsPermissions.requestScreenRecording()
    }

    private func exportProfile() {
        guard let data = settings.exportProfile() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Aeroshot-Profile.json"
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
