import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let hosting = NSHostingController(rootView: SettingsWindow()
            .environmentObject(appState.settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "ScreenCapture Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 420))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        HotkeyManager.requestInputMonitoringAccess()
        HotkeyManager.shared.refreshMonitors()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
