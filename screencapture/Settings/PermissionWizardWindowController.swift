import AppKit
import SwiftUI

@MainActor
final class PermissionWizardWindowController: NSWindowController {
    private unowned let appState: AppState
    private let onComplete: () -> Void

    init(appState: AppState, onComplete: @escaping () -> Void) {
        self.appState = appState
        self.onComplete = onComplete
        let hosting = NSHostingController(
            rootView: PermissionWizardView(onComplete: onComplete)
                .environmentObject(appState.settings)
        )

        let window = NSWindow(contentViewController: hosting)
        window.title = "Permissions"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: 480, height: 520))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Wizard

private struct WizardPermission: Identifiable {
    let id: String
    let title: String
    let detail: String
    let optional: Bool
    let granted: () -> Bool
    let openSettings: () -> Void
}

struct PermissionWizardView: View {
    @EnvironmentObject var settings: SettingsStore
    let onComplete: () -> Void

    @State private var refreshToken = UUID()

    private var permissions: [WizardPermission] {
        [
            WizardPermission(
                id: "screen",
                title: "Screen Recording",
                detail: "Required for area, window, full-screen, and video capture.",
                optional: false,
                granted: { SettingsPermissions.screenRecordingGranted },
                openSettings: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            ),
            WizardPermission(
                id: "input",
                title: "Input Monitoring",
                detail: "Required for global shortcuts (for example ⌃⌥A for All-in-One).",
                optional: false,
                granted: { SettingsPermissions.inputMonitoringGranted },
                openSettings: { HotkeyManager.openInputMonitoringSettings() }
            ),
            WizardPermission(
                id: "accessibility",
                title: "Accessibility",
                detail: "Optional. Needed only for automatic scrolling in scrolling capture.",
                optional: true,
                granted: { SettingsPermissions.accessibilityGranted },
                openSettings: { ScrollEventPoster.openAccessibilitySettings() }
            )
        ]
    }

    private var grantedCount: Int {
        permissions.filter { $0.granted() }.count
    }

    private var requiredGranted: Bool {
        permissions.filter { !$0.optional }.allSatisfy { $0.granted() }
    }

    private var nextMissing: WizardPermission? {
        permissions.first { !$0.granted() }
    }

    var body: some View {
        ZStack {
            SettingsShellBackground()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                        header

                        SettingsPanel("Required access") {
                            VStack(spacing: 0) {
                                ForEach(Array(permissions.enumerated()), id: \.element.id) { index, permission in
                                    if index > 0 {
                                        Divider().opacity(0.5)
                                    }
                                    SettingsPermissionTile(
                                        title: permission.title,
                                        description: permission.detail,
                                        granted: permission.granted(),
                                        openSettings: permission.openSettings
                                    )
                                }
                            }
                        }
                        .id(refreshToken)

                        if let nextMissing, !nextMissing.granted() {
                            Text(footerHint(for: nextMissing))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: SettingsTheme.spacingS) {
                            Image(systemName: "menubar.rectangle")
                                .foregroundStyle(.secondary)
                            Text("ScreenCapture runs from the menu bar. No dock icon.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 420, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SettingsTheme.spacingL)
                    .padding(.top, SettingsTheme.spacingXL)
                }

                Divider().opacity(0.5)

                footer
                    .padding(.horizontal, SettingsTheme.spacingL)
                    .padding(.vertical, SettingsTheme.spacingM)
            }
        }
        .frame(width: 480, height: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshToken = UUID()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
            HStack(spacing: SettingsTheme.spacingM) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SettingsTheme.spacingXS) {
                    Text("Before your first capture")
                        .font(.title2.bold())
                    Text("Grant access in System Settings, then return here. \(grantedCount) of \(permissions.count) approved.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Not now") {
                settings.hasCompletedOnboarding = true
                onComplete()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            if let next = nextMissing, !requiredGranted {
                Button(primaryLabel(for: next)) {
                    next.openSettings()
                    SettingsTheme.performHaptic()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Done") {
                    settings.hasCompletedOnboarding = true
                    onComplete()
                    SettingsTheme.performHaptic()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func primaryLabel(for permission: WizardPermission) -> String {
        "Grant \(permission.title)…"
    }

    private func footerHint(for permission: WizardPermission) -> String {
        if permission.optional {
            return "Accessibility is optional. Grant it only if you use scrolling capture with auto-scroll."
        }
        return "Open System Settings, enable ScreenCapture for \(permission.title), then return to this window."
    }
}
