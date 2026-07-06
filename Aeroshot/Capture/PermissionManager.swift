import Combine
import AppKit
import ScreenCaptureKit

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var hasPermission: Bool = false

    /// Avoid spamming the Screen Recording sheet when the user already approved TCC
    /// but ScreenCaptureKit returns a transient error.
    private var didPromptScreenCaptureThisSession = false

    func preflight() -> Bool {
        let ok = CGPreflightScreenCaptureAccess()
        hasPermission = ok
        return ok
    }

    /// Ensures we can capture. Returns true if permission is available.
    /// Only triggers the system prompt when TCC preflight says access is missing.
    @discardableResult
    func ensurePermission() async -> Bool {
        if preflight() {
            // Preflight is authoritative for whether we should show the TCC sheet.
            // ScreenCaptureKit can fail transiently even when access is granted.
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            hasPermission = true
            return true
        }

        guard !didPromptScreenCaptureThisSession else {
            hasPermission = false
            return false
        }
        didPromptScreenCaptureThisSession = true

        let granted = CGRequestScreenCaptureAccess()
        if !granted {
            showOnboardingAlert()
        }
        hasPermission = granted
        return granted
    }

    private func showOnboardingAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Needed"
        alert.informativeText = "Aeroshot needs Screen Recording access to take screenshots.\n\nEnable it in System Settings → Privacy & Security → Screen Recording, then relaunch the app."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Relaunch")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            SettingsPermissions.openScreenRecordingSettings()
        case .alertSecondButtonReturn:
            relaunch()
        default:
            break
        }
    }

    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
