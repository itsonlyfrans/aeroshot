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
    @State private var permissionsExpanded = !SettingsPermissions.allGranted
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
        SettingsPaneLayout(pane: .system) {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                appHero

                if !SettingsPermissions.allGranted {
                    SettingsInlineCallout(
                        symbol: "exclamationmark.shield.fill",
                        message: "\(SettingsPermissions.healthLabel). Grant missing access for full functionality.",
                        tone: .warning,
                        buttonTitle: "Open System Settings"
                    ) {
                        if !SettingsPermissions.screenRecordingGranted {
                            SettingsPermissions.requestScreenRecording()
                        } else if !SettingsPermissions.accessibilityGranted {
                            SettingsPermissions.requestAccessibility()
                        } else {
                            Task {
                                if !SettingsPermissions.microphoneGranted {
                                    await SettingsPermissions.requestMicrophone()
                                } else if !SettingsPermissions.cameraGranted {
                                    await SettingsPermissions.requestCamera()
                                }
                                refreshPermissions()
                            }
                        }
                    }
                }

                SettingsPanel("Permissions", symbol: "lock.shield") {
                    SettingsDisclosureRow(
                        title: "Permissions overview",
                        subtitle: "Review and grant everything Aeroshot can use.",
                        badgeText: SettingsPermissions.healthLabel,
                        badgeTone: SettingsPermissions.allGranted ? .success : .warning,
                        isExpanded: $permissionsExpanded
                    ) {
                        SettingsPermissionTile(
                            title: "Screen Recording",
                            description: "Required to capture windows, areas, and video.",
                            granted: SettingsPermissions.screenRecordingGranted,
                            openSettings: { SettingsPermissions.requestScreenRecording() }
                        )

                        SettingsSeparator()

                        SettingsPermissionTile(
                            title: "Accessibility",
                            description: "Required for global shortcuts, click highlights, and scrolling auto-scroll.",
                            granted: SettingsPermissions.accessibilityGranted,
                            openSettings: { SettingsPermissions.requestAccessibility() }
                        )

                        SettingsSeparator()

                        SettingsPermissionTile(
                            title: "Microphone",
                            description: "Optional voice audio in screen recordings.",
                            granted: SettingsPermissions.microphoneGranted,
                            required: false,
                            openSettings: {
                                Task {
                                    await SettingsPermissions.requestMicrophone()
                                    refreshPermissions()
                                }
                            }
                        )

                        SettingsSeparator()

                        SettingsPermissionTile(
                            title: "Camera",
                            description: "Optional webcam overlay in screen recordings.",
                            granted: SettingsPermissions.cameraGranted,
                            required: false,
                            openSettings: {
                                Task {
                                    await SettingsPermissions.requestCamera()
                                    refreshPermissions()
                                }
                            }
                        )

                        SettingsSeparator()

                        SettingsLinkButton(title: "Open setup guide", symbol: "book") {
                            appState.showPermissionWizard()
                        }
                        .padding(.top, SettingsTheme.spacingXS)
                    }
                }
                .id(permissionRefreshTick)

                SettingsPanel("App presence", symbol: "menubar.rectangle") {
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
                        SettingsInlineCallout(
                            symbol: "eye.slash",
                            message: "Background mode — use keyboard shortcuts, Shortcuts, or AppleScript. Reopen the app to reach Settings.",
                            tone: .info
                        )
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

                    SettingsSeparator()

                    VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                        SettingsSubsectionHeader(
                            title: "Settings profile",
                            subtitle: "Share capture preferences; cloud upload destinations stay on this Mac."
                        )

                        HStack(spacing: SettingsTheme.spacingM) {
                            AeroChipButton("Export profile…", symbol: "square.and.arrow.up") { exportProfile() }
                            AeroChipButton("Import profile…", symbol: "square.and.arrow.down") { importProfile() }
                            Button("Reset all to defaults") { profileAlert = .resetConfirm }
                                .buttonStyle(AeroButtonStyle(kind: .destructive, size: .compact))
                        }
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
                    .shadow(
                        color: Color.black.opacity(AeroTokens.Elevation.card.opacity),
                        radius: AeroTokens.Elevation.card.radius,
                        y: AeroTokens.Elevation.card.y
                    )
            }

            VStack(alignment: .leading, spacing: SettingsTheme.spacingXS) {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Aeroshot")
                    .font(.title2.bold())
                Text("Version \(versionString)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: "© \(Calendar.current.component(.year, from: Date())) Aeroshot")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: SettingsTheme.spacingXS) {
                SettingsStatusBadge(
                    text: SettingsPermissions.healthLabel,
                    tone: SettingsPermissions.allGranted ? .success : .warning
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
        // Never hide a problem behind a disclosure — auto-expand when
        // anything is missing while the group is collapsed.
        if !SettingsPermissions.allGranted && !permissionsExpanded {
            permissionsExpanded = true
        }
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
