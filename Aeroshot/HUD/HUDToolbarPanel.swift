import AppKit
import SwiftUI

/// Floating toolbar for the All-in-One capture HUD.
@MainActor
final class HUDToolbarPanel {
    private var panel: NSPanel?
    private var model: HUDToolbarModel?
    private var mouseMonitor: Any?

    func show(selected: CaptureIntent,
              onSelect: @escaping (CaptureIntent) -> Void,
              onCancel: @escaping () -> Void) {
        dismiss()

        let model = HUDToolbarModel(selected: selected)
        model.onSelect = onSelect
        model.onCancel = onCancel
        self.model = model

        let hosting = HUDToolbarHostingView(rootView: HUDToolbarView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        hosting.layoutSubtreeIfNeeded()
        let panelSize = NSSize(width: max(396, ceil(hosting.fittingSize.width + 24)), height: 96)
        hosting.frame = NSRect(origin: .zero, size: panelSize)

        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.contentView = hosting
        self.panel = panel
        installPointerMonitor(for: panel)

        DispatchQueue.main.async { [weak self] in
            self?.positionAndShowPanel()
        }
    }

    private func positionAndShowPanel() {
        guard let panel else { return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let screen {
            let vf = screen.visibleFrame
            let panelSize = panel.frame.size
            let x = min(max(mouse.x - panelSize.width / 2, vf.minX + 12), vf.maxX - panelSize.width - 12)
            let below = mouse.y - panelSize.height - 22
            let y = below >= vf.minY + 12 ? below : min(mouse.y + 22, vf.maxY - panelSize.height - 12)
            let origin = NSPoint(
                x: x,
                y: y
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        updatePointerCursor(inside: panel.frame.contains(NSEvent.mouseLocation))
    }

    func setSelected(_ intent: CaptureIntent) {
        DispatchQueue.main.async { [weak self] in
            withAnimation(.easeOut(duration: 0.14)) {
                self?.model?.selected = intent
            }
        }
    }

    func dismiss() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        model = nil
        updatePointerCursor(inside: false)
    }

    /// The selection overlay remains active behind this non-activating panel.
    /// Reassert after event dispatch so its cursor update cannot overwrite the
    /// toolbar's interaction cursor while the pointer is inside the HUD frame.
    private func installPointerMonitor(for panel: NSPanel) {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .leftMouseUp]) { [weak self, weak panel] event in
            guard let self, let panel else { return event }
            DispatchQueue.main.async {
                self.updatePointerCursor(inside: panel.frame.contains(NSEvent.mouseLocation))
            }
            return event
        }
    }

    private func updatePointerCursor(inside: Bool) {
        HUDCursor.isPointerOverToolbar = inside
        if inside {
            HUDCursor.command.set()
        }
    }
}

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .cursorUpdate:
            if HUDCursor.isPointerOverToolbar {
                HUDCursor.command.set()
            }
        default:
            break
        }
        super.sendEvent(event)
    }
}

/// The selection overlay owns a precision cursor. This hosting view explicitly
/// claims the ordinary arrow while the pointer is over command chrome, so the
/// cursor always reflects the interaction currently available.
private final class HUDToolbarHostingView: NSHostingView<HUDToolbarView> {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: HUDCursor.command)
    }

    override func cursorUpdate(with event: NSEvent) {
        HUDCursor.command.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }
}
