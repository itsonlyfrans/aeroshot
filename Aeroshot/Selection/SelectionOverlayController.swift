import AppKit
import ScreenCaptureKit

enum SelectionMode {
    case area
    case window
    case scrolling
}

enum SelectionResult {
    case area(cocoaRect: CGRect, display: DisplayInfo)
    case window(WindowEnumerator.WindowInfo)
}

/// Presents one borderless, non-activating panel per screen for area/window
/// selection. Calls completion exactly once (nil = cancelled).
@MainActor
final class SelectionOverlayController {

    private var panels: [SelectionPanel] = []
    private let displays: [DisplayInfo]
    private let windows: [WindowEnumerator.WindowInfo]
    private let frozenImages: [CGDirectDisplayID: CGImage]
    private(set) var mode: SelectionMode
    private(set) var aspectLock: SelectionAspectLock
    private var completion: ((SelectionResult?) -> Void)?
    private var keyMonitor: Any?
    /// Called before default Esc handling; return true to swallow the event.
    var extraKeyHandler: ((NSEvent) -> Bool)?

    init(displays: [DisplayInfo],
         windows: [WindowEnumerator.WindowInfo],
         frozenImages: [CGDirectDisplayID: CGImage],
         mode: SelectionMode,
         aspectLock: SelectionAspectLock = .auto,
         completion: @escaping (SelectionResult?) -> Void) {
        self.displays = displays
        self.windows = windows
        self.frozenImages = frozenImages
        self.mode = mode
        self.aspectLock = aspectLock
        self.completion = completion
    }

    func present() {
        for display in displays {
            let panel = SelectionPanel(contentRect: display.nsScreen.frame,
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.acceptsMouseMovedEvents = true

            let displayWindows = WindowEnumerator.windows(on: display, in: windows)
            let view = SelectionOverlayView(display: display,
                                            windows: displayWindows,
                                            frozenImage: frozenImages[display.displayID],
                                            mode: mode,
                                            aspectLock: aspectLock)
            view.onCommit = { [weak self] result in self?.finish(with: result) }
            view.onCancel = { [weak self] in self?.finish(with: nil) }
            panel.contentView = view
            panel.setFrame(display.nsScreen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        focusActivePanel()
        // Global Esc handling even if no panel is key.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.extraKeyHandler?(event) == true { return nil }
            if event.keyCode == 53 { // Esc
                self.finish(with: nil)
                return nil
            }
            return event
        }
        NSCursor.crosshair.set()
    }

    /// Key the overlay panel under the cursor so the first click starts selection immediately.
    func focusActivePanel() {
        let mouse = NSEvent.mouseLocation
        let panel = panels.first { $0.frame.contains(mouse) } ?? panels.first
        guard let panel, let view = panel.contentView else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    func setAspectLock(_ lock: SelectionAspectLock) {
        aspectLock = lock
        for panel in panels {
            (panel.contentView as? SelectionOverlayView)?.setAspectLock(lock)
        }
    }

    func setMode(_ newMode: SelectionMode) {
        mode = newMode
        for panel in panels {
            (panel.contentView as? SelectionOverlayView)?.setMode(newMode)
        }
    }

    func dismiss() {
        guard completion != nil else { return }
        finish(with: nil)
    }

    private func finish(with result: SelectionResult?) {
        guard let completion else { return }
        self.completion = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        NSCursor.arrow.set()
        // Give the window server a beat to remove the overlay before capturing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            completion(result)
        }
    }
}

/// Panel subclass that can become key so Esc and arrow nudges work
/// without activating the app.
final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
