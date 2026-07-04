import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let hosting = NSHostingController(rootView: SettingsWindow()
            .environmentObject(appState.settings)
            .environmentObject(appState))
        let window = NSWindow(contentViewController: hosting)
        window.title = "ScreenCapture Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 820, height: 560))
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("SettingsWindow")
        if !window.setFrameUsingName("SettingsWindow") {
            window.center()
        }
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
