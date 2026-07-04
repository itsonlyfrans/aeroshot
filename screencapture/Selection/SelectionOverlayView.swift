import AppKit

/// Per-screen selection view: dimming, rubber-band, crosshair, dimension
/// label, magnifier loupe, and window hover-highlight (in window mode).
final class SelectionOverlayView: NSView {

    var onCommit: ((SelectionResult) -> Void)?
    var onCancel: (() -> Void)?

    private let display: DisplayInfo
    private let windows: [WindowEnumerator.WindowInfo]
    private let mode: SelectionMode
    private let magnifier: MagnifierView

    private var dragStart: NSPoint?          // view-local
    private var currentPoint: NSPoint?       // view-local
    private var hoveredWindow: WindowEnumerator.WindowInfo?
    private var trackingArea: NSTrackingArea?

    init(display: DisplayInfo,
         windows: [WindowEnumerator.WindowInfo],
         frozenImage: CGImage?,
         mode: SelectionMode) {
        self.display = display
        self.windows = windows
        self.mode = mode
        self.magnifier = MagnifierView(frozenImage: frozenImage, display: display)
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(magnifier)
        magnifier.isHidden = (mode == .window)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeAlways, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Coordinate helpers

    private func globalPoint(for local: NSPoint) -> NSPoint {
        guard let window else { return local }
        let inWindow = convert(local, to: nil)
        return window.convertPoint(toScreen: inWindow)
    }

    private func localRect(fromGlobalCocoa rect: CGRect) -> CGRect {
        guard let window else { return rect }
        let inWindow = window.convertFromScreen(rect)
        return convert(inWindow, from: nil)
    }

    private var selectionRectLocal: CGRect? {
        guard let dragStart, let currentPoint else { return nil }
        return CGRect(x: min(dragStart.x, currentPoint.x),
                      y: min(dragStart.y, currentPoint.y),
                      width: abs(currentPoint.x - dragStart.x),
                      height: abs(currentPoint.y - dragStart.y))
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        currentPoint = local
        if mode == .window {
            let global = globalPoint(for: local)
            hoveredWindow = WindowEnumerator.window(at: global, in: windows)
        }
        updateMagnifier(at: local)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if mode == .window {
            if let hoveredWindow {
                onCommit?(.window(hoveredWindow))
            } else {
                onCancel?()
            }
            return
        }
        dragStart = local
        currentPoint = local
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .area else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        updateMagnifier(at: currentPoint!)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .area else { return }
        guard let rect = selectionRectLocal, rect.width >= 2, rect.height >= 2 else {
            dragStart = nil
            needsDisplay = true
            return
        }
        commitArea(rect)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onCancel?()
        case 36, 76: // Return / Enter — commit current selection if any
            if let rect = selectionRectLocal, rect.width >= 2, rect.height >= 2 {
                commitArea(rect)
            }
        default:
            super.keyDown(with: event)
        }
    }

    private func commitArea(_ localRect: CGRect) {
        // Snap to whole points so pixels align at any scale.
        let snapped = CGRect(x: localRect.origin.x.rounded(.down),
                             y: localRect.origin.y.rounded(.down),
                             width: localRect.width.rounded(),
                             height: localRect.height.rounded())
        guard let window else { return }
        let inWindow = convert(snapped, to: nil)
        let global = window.convertToScreen(inWindow)
        onCommit?(.area(cocoaRect: global, display: display))
    }

    private func updateMagnifier(at local: NSPoint) {
        guard mode == .area else { return }
        magnifier.update(cursorLocal: local, in: self)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Dim the whole screen.
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fill(bounds)

        if mode == .window {
            if let hoveredWindow {
                let rect = localRect(fromGlobalCocoa: hoveredWindow.cocoaFrame).intersection(bounds)
                if !rect.isNull, !rect.isEmpty {
                    ctx.clear(rect)
                    ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor)
                    ctx.fill(rect)
                    ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
                    ctx.setLineWidth(2)
                    ctx.stroke(rect.insetBy(dx: 1, dy: 1))
                    drawLabel("\(hoveredWindow.appName)\(hoveredWindow.title.isEmpty ? "" : " — \(hoveredWindow.title)")",
                              near: rect, in: ctx)
                }
            }
            return
        }

        // Area mode: crosshair before drag, rubber band during.
        if let rect = selectionRectLocal, dragStart != nil {
            ctx.clear(rect)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
            drawLabel("\(Int((rect.width * display.scale).rounded())) × \(Int((rect.height * display.scale).rounded()))",
                      near: rect, in: ctx)
        } else if let p = currentPoint {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeLineSegments(between: [CGPoint(x: 0, y: p.y), CGPoint(x: bounds.width, y: p.y)])
            ctx.strokeLineSegments(between: [CGPoint(x: p.x, y: 0), CGPoint(x: p.x, y: bounds.height)])
        }
    }

    private func drawLabel(_ text: String, near rect: CGRect, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 8)
        if origin.y < 4 { origin.y = rect.minY + 8 }
        origin.x = max(4, min(origin.x, bounds.width - size.width - 4))
        let bg = CGRect(x: origin.x - 6, y: origin.y - 3, width: size.width + 12, height: size.height + 6)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        let path = CGPath(roundedRect: bg, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        str.draw(at: origin)
    }
}
