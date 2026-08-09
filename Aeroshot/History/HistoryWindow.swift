import AppKit
import SwiftUI

/// The library is presented as a tray-sized panel. It is still owned by
/// `AppState`, so existing menu, shortcut, scripting, and capture routes keep
/// one controller alive instead of creating a new window for every toggle.
@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let hosting = NSHostingController(rootView: CaptureTrayView(appState: appState)
            .environmentObject(appState.history))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Aeroshot Capture Tray"
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: 1_080, height: 900))
        window.minSize = NSSize(width: 860, height: 620)
        if let visibleFrame = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: visibleFrame.maxX - 1_100,
                y: visibleFrame.minY + 20
            ))
        } else {
            window.center()
        }
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func toggle() {
        guard let window else {
            show()
            return
        }
        if window.isVisible { window.orderOut(nil) } else { show() }
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the panel is equivalent to hiding it. AppState retains the
        // controller so a later shortcut can restore the same tray state.
        window?.orderOut(nil)
    }

}
