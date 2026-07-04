import Combine
import AppKit
import ScreenCaptureKit

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var hasPermission: Bool = false

    func preflight() -> Bool {
        let ok = CGPreflightScreenCaptureAccess()
        hasPermission = ok
        return ok
    }

    /// Ensures we can capture. Returns true if permission is available.
    /// If not, triggers the system prompt and shows guidance.
    @discardableResult
    func ensurePermission() async -> Bool {
        if preflight() {
            // Runtime truth: SCShareableContent throws if TCC is actually denied.
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                hasPermission = true
                return true
            } catch {
                hasPermission = false
            }
        }
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
        alert.informativeText = "ScreenCapture needs Screen Recording access to take screenshots.\n\nEnable it in System Settings → Privacy & Security → Screen Recording, then relaunch the app."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Relaunch")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
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
