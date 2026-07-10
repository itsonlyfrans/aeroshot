import AppKit

/// Draws ephemeral click ripples on screen during recording so they appear in the capture.
@MainActor
final class ClickHighlightController {
    var onClick: ((CGPoint) -> Void)?

    private var monitor: Any?
    private var panels: [ClickRipplePanel] = []

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                let point = NSEvent.mouseLocation
                self?.onClick?(point)
                self?.showRipple(at: point)
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
    }

    private func showRipple(at screenPoint: NSPoint) {
        let size: CGFloat = 80
        let frame = NSRect(x: screenPoint.x - size / 2,
                           y: screenPoint.y - size / 2,
                           width: size,
                           height: size)
        let panel = ClickRipplePanel(contentRect: frame,
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered,
                                     defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = ClickRippleView(frame: NSRect(origin: .zero, size: frame.size))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        panels.append(panel)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
                guard let self, let panel else { return }
                self.panels.removeAll { $0 === panel }
            }
        }
    }
}

private final class ClickRipplePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ClickRippleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 8
        let rect = bounds.insetBy(dx: inset, dy: inset)
        NSColor.systemYellow.withAlphaComponent(0.55).setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = 4
        path.stroke()
        NSColor.systemYellow.withAlphaComponent(0.2).setFill()
        path.fill()
    }
}
