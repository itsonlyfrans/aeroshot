import AppKit
import ScreenCaptureKit

/// Per-screen selection view: dimming, rubber-band, crosshair, dimension
/// label, magnifier loupe, and window hover-highlight (in window mode).
final class SelectionOverlayView: NSView {

    var onCommit: ((SelectionResult) -> Void)?
    var onCancel: (() -> Void)?

    private let display: DisplayInfo
    private let windows: [WindowEnumerator.WindowInfo]
    private var mode: SelectionMode
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

    func setMode(_ newMode: SelectionMode) {
        mode = newMode
        dragStart = nil
        currentPoint = nil
        hoveredWindow = nil
        magnifier.isHidden = (mode == .window)
        needsDisplay = true
        if mode == .window {
            NSCursor.arrow.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

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

    /// Map an SCK window frame to this overlay view's local coordinates.
    private func localRect(fromSCFrame scFrame: CGRect) -> CGRect {
        let df = display.scDisplay.frame
        let topLeft = CGRect(x: scFrame.origin.x - df.origin.x,
                             y: scFrame.origin.y - df.origin.y,
                             width: scFrame.width,
                             height: scFrame.height)
        return CGRect(x: topLeft.origin.x,
                      y: bounds.height - topLeft.maxY,
                      width: topLeft.width,
                      height: topLeft.height)
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
            hoveredWindow = WindowEnumerator.frontmostWindow(at: NSEvent.mouseLocation, candidates: windows)
        }
        updateMagnifier(at: local)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if mode == .window {
            guard let hit = WindowEnumerator.frontmostWindow(at: NSEvent.mouseLocation, candidates: windows) else {
                onCancel?()
                return
            }
            onCommit?(.window(hit))
            return
        }
        dragStart = local
        currentPoint = local
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .area || mode == .scrolling else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        updateMagnifier(at: currentPoint!)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .area || mode == .scrolling else { return }
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
        case 123, 124, 125, 126: // ← → ↓ ↑
            if mode == .area || mode == .scrolling {
                nudgeSelection(keyCode: event.keyCode, bigStep: event.modifierFlags.contains(.shift))
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }

    /// Arrow keys move the active rubber-band by 1 pt (10 pt with ⇧).
    private func nudgeSelection(keyCode: UInt16, bigStep: Bool) {
        let step = bigStep ? 10.0 : 1.0
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        switch keyCode {
        case 123: dx = -step
        case 124: dx = step
        case 125: dy = -step
        case 126: dy = step
        default: return
        }

        if dragStart != nil, currentPoint != nil {
            dragStart?.x += dx
            dragStart?.y += dy
            currentPoint?.x += dx
            currentPoint?.y += dy
        } else if var point = currentPoint {
            point.x += dx
            point.y += dy
            point.x = min(max(point.x, 0), bounds.width)
            point.y = min(max(point.y, 0), bounds.height)
            currentPoint = point
        } else {
            return
        }

        clampSelectionToBounds()
        if let point = currentPoint { updateMagnifier(at: point) }
        needsDisplay = true
    }

    private func clampSelectionToBounds() {
        guard var start = dragStart, var end = currentPoint else { return }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        var shiftX: CGFloat = 0
        var shiftY: CGFloat = 0
        if rect.minX < 0 { shiftX = -rect.minX }
        if rect.maxX > bounds.width { shiftX = bounds.width - rect.maxX }
        if rect.minY < 0 { shiftY = -rect.minY }
        if rect.maxY > bounds.height { shiftY = bounds.height - rect.maxY }
        guard shiftX != 0 || shiftY != 0 else { return }
        start.x += shiftX
        start.y += shiftY
        end.x += shiftX
        end.y += shiftY
        dragStart = start
        currentPoint = end
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
        guard mode != .window else { return }
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
                let rect = localRect(fromSCFrame: hoveredWindow.scFrame).intersection(bounds)
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

        if mode == .scrolling, selectionRectLocal == nil {
            drawInstruction("Drag to select the scroll region", in: ctx)
        }

        // Area / scrolling mode: crosshair before drag, rubber band during.
        if let rect = selectionRectLocal, dragStart != nil {
            ctx.clear(rect)
            
            ctx.saveGState()
            // Soft double stroke with drop shadow
            ctx.setShadow(offset: .zero, blur: 5, color: NSColor.black.withAlphaComponent(0.4).cgColor)
            
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(rect.insetBy(dx: 0.75, dy: 0.75))
            
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.0)
            ctx.stroke(rect)
            ctx.restoreGState()

            drawLabel("\(Int((rect.width * display.scale).rounded())) × \(Int((rect.height * display.scale).rounded()))",
                      near: rect, in: ctx)
        } else if let p = currentPoint {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(0.75)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.strokeLineSegments(between: [CGPoint(x: 0, y: p.y), CGPoint(x: bounds.width, y: p.y)])
            ctx.strokeLineSegments(between: [CGPoint(x: p.x, y: 0), CGPoint(x: p.x, y: bounds.height)])
            ctx.restoreGState()
            
            // Draw floating (X, Y) blueprint coordinates
            drawLabel("X: \(Int(p.x * display.scale))  Y: \(Int((bounds.height - p.y) * display.scale))",
                      near: CGRect(x: p.x + 8, y: p.y + 8, width: 0, height: 0), in: ctx)
        }
    }

    private func drawLabel(_ text: String, near rect: CGRect, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 10)
        if origin.y < 4 { origin.y = rect.minY + 10 }
        origin.x = max(4, min(origin.x, bounds.width - size.width - 4))
        
        let bg = CGRect(x: origin.x - 8, y: origin.y - 3, width: size.width + 16, height: size.height + 6)
        ctx.saveGState()
        ctx.setFillColor(NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.85).cgColor)
        ctx.addPath(CGPath(roundedRect: bg, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.fillPath()
        
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(CGPath(roundedRect: bg.insetBy(dx: 0.25, dy: 0.25), cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.strokePath()
        ctx.restoreGState()
        
        str.draw(at: origin)
    }

    private func drawInstruction(_ text: String, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - size.height - 44)
        let bg = CGRect(x: origin.x - 12, y: origin.y - 4, width: size.width + 24, height: size.height + 8)
        
        ctx.saveGState()
        ctx.setFillColor(NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.85).cgColor)
        ctx.addPath(CGPath(roundedRect: bg, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()
        
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(CGPath(roundedRect: bg.insetBy(dx: 0.25, dy: 0.25), cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.strokePath()
        ctx.restoreGState()
        
        str.draw(at: origin)
    }
}
