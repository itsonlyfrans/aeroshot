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
        window.title = "Aeroshot Settings"
        // The chrome owns its own headers (sidebar app mark + pinned pane title),
        // so the floating system title text stays hidden; the title string
        // remains for Mission Control and accessibility.
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1180, height: 820))
        window.contentMinSize = NSSize(width: 980, height: 680)
        window.contentMaxSize = NSSize(width: 1500, height: 1080)
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("SettingsWindowAtlas")
        if !window.setFrameUsingName("SettingsWindowAtlas") {
            window.center()
        }
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        HotkeyManager.requestGlobalHotkeyAccess()
        HotkeyManager.shared.refreshMonitors()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
    }
}
