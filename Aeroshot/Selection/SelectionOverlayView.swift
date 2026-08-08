import AppKit
import ScreenCaptureKit

/// Per-screen selection view: dimming, rubber-band, crosshair, dimension
/// label, drag-only loupe, and window hover-highlight.
final class SelectionOverlayView: NSView {

    var onCommit: ((SelectionResult) -> Void)?
    var onCancel: (() -> Void)?
    var onSelectionBegan: (() -> Void)?

    private let display: DisplayInfo
    private let windows: [WindowEnumerator.WindowInfo]
    private let frozenImage: CGImage?
    private var mode: SelectionMode
    private var aspectLock: SelectionAspectLock
    private var freezesScreen: Bool
    private let magnifier: MagnifierView

    private var dragStart: NSPoint?          // view-local
    private var currentPoint: NSPoint?       // view-local
    private var hoveredWindow: WindowEnumerator.WindowInfo?
    private var clickedWindow: WindowEnumerator.WindowInfo?
    private var screenSelected = false
    private var selectionRetained = false
    private var didDrag = false
    private var trackingArea: NSTrackingArea?

    init(display: DisplayInfo,
         windows: [WindowEnumerator.WindowInfo],
         frozenImage: CGImage?,
         freezesScreen: Bool = false,
         mode: SelectionMode,
         aspectLock: SelectionAspectLock = .auto) {
        self.display = display
        self.windows = windows
        self.frozenImage = frozenImage
        self.mode = mode
        self.aspectLock = aspectLock
        self.freezesScreen = freezesScreen
        self.magnifier = MagnifierView(frozenImage: frozenImage, display: display)
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(magnifier)
        // The loupe is a precision aid while dragging, never an idle overlay.
        magnifier.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func setAspectLock(_ lock: SelectionAspectLock) {
        aspectLock = lock
        needsDisplay = true
    }

    func setFreezesScreen(_ enabled: Bool) {
        freezesScreen = enabled
        needsDisplay = true
    }

    func setMode(_ newMode: SelectionMode) {
        mode = newMode
        dragStart = nil
        currentPoint = nil
        hoveredWindow = nil
        clickedWindow = nil
        screenSelected = false
        selectionRetained = false
        didDrag = false
        magnifier.isHidden = true
        needsDisplay = true
        activateSelectionCursor()
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var selectionCursor: NSCursor {
        mode == .window || mode == .screen ? .arrow : SelectionCursor.crosshair
    }

    /// The overlay is the single owner of its cursor. Calling this after the
    /// panel is ordered front also covers the first frame before AppKit sends a
    /// cursor-update event.
    func activateSelectionCursor() {
        guard !HUDCursor.isPointerOverToolbar else {
            HUDCursor.command.set()
            return
        }
        window?.invalidateCursorRects(for: self)
        selectionCursor.set()
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: selectionCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !HUDCursor.isPointerOverToolbar else {
            HUDCursor.command.set()
            return
        }
        selectionCursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        activateSelectionCursor()
    }

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

    /// Seed the overlay from the pointer's existing screen position so guides
    /// render on the first frame instead of waiting for a mouse-moved event.
    func primePointer(at screenPoint: NSPoint) {
        guard let window else { return }
        let pointInWindow = window.convertPoint(fromScreen: screenPoint)
        updatePointer(local: convert(pointInWindow, from: nil), screenPoint: screenPoint)
    }

    private func updatePointer(local: NSPoint, screenPoint: NSPoint) {
        if selectionRetained { return }
        currentPoint = local
        if mode == .window || (mode == .hybrid && dragStart == nil) {
            hoveredWindow = WindowEnumerator.frontmostWindow(at: screenPoint, candidates: windows)
        } else {
            hoveredWindow = nil
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        activateSelectionCursor()
        let local = convert(event.locationInWindow, from: nil)
        updatePointer(local: local, screenPoint: NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        activateSelectionCursor()
        let local = convert(event.locationInWindow, from: nil)
        if mode == .screen {
            onCommit?(.screen(display))
            return
        }
        if mode == .window {
            guard let hit = WindowEnumerator.frontmostWindow(at: NSEvent.mouseLocation, candidates: windows) else {
                onCancel?()
                return
            }
            clickedWindow = hit
            onCommit?(.window(hit))
            return
        }
        clickedWindow = mode == .hybrid
            ? WindowEnumerator.frontmostWindow(at: NSEvent.mouseLocation, candidates: windows)
            : nil
        selectionRetained = false
        didDrag = false
        dragStart = local
        currentPoint = local
        magnifier.isHidden = true
        onSelectionBegan?()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        activateSelectionCursor()
        guard mode != .window, mode != .screen else { return }
        var point = convert(event.locationInWindow, from: nil)
        if let start = dragStart {
            didDrag = didDrag || abs(point.x - start.x) >= 2 || abs(point.y - start.y) >= 2
        }
        if let start = dragStart, aspectLock.ratio != nil {
            let constrained = SelectionAspectLock.constrainedRect(
                origin: start,
                current: point,
                ratio: aspectLock.ratio!,
                bounds: bounds
            )
            dragStart = constrained.origin
            point = constrained.current
        }
        currentPoint = point
        updateMagnifier(at: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode != .window, mode != .screen else { return }
        if mode == .hybrid, !didDrag, let clickedWindow {
            onCommit?(.window(clickedWindow))
            return
        }
        guard let rect = selectionRectLocal, rect.width >= 2, rect.height >= 2 else {
            dragStart = nil
            clickedWindow = nil
            didDrag = false
            magnifier.isHidden = true
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
            if mode != .window, mode != .screen {
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
        if let start = dragStart, let end = currentPoint, let ratio = aspectLock.ratio {
            let constrained = SelectionAspectLock.constrainedRect(
                origin: start,
                current: end,
                ratio: ratio,
                bounds: bounds
            )
            dragStart = constrained.origin
            currentPoint = constrained.current
        }
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

    func retainSelection(_ result: SelectionResult) {
        dragStart = nil
        currentPoint = nil
        clickedWindow = nil
        hoveredWindow = nil
        screenSelected = false
        selectionRetained = false
        magnifier.isHidden = true

        switch result {
        case .area(let rect, let selectedDisplay) where selectedDisplay.displayID == display.displayID:
            let local = localRect(fromGlobalCocoa: rect)
            dragStart = local.origin
            currentPoint = NSPoint(x: local.maxX, y: local.maxY)
            selectionRetained = true
        case .window(let window) where window.scFrame.intersects(display.scDisplay.frame):
            clickedWindow = window
            selectionRetained = true
        case .screen(let selectedDisplay) where selectedDisplay.displayID == display.displayID:
            screenSelected = true
            selectionRetained = true
        default:
            break
        }
        needsDisplay = true
    }

    private func updateMagnifier(at local: NSPoint) {
        guard mode != .window, mode != .screen, dragStart != nil else { return }
        magnifier.update(cursorLocal: local, in: self)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        if freezesScreen, let frozenImage {
            ctx.interpolationQuality = .none
            ctx.draw(frozenImage, in: bounds)
        }

        // Dim the whole screen.
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fill(bounds)

        if mode == .screen {
            if screenSelected {
                reveal(bounds, in: ctx)
                ctx.setStrokeColor(AeroTheme.accentNSColor.cgColor)
                ctx.setLineWidth(4)
                ctx.stroke(bounds.insetBy(dx: 2, dy: 2))
                drawInstruction("Screen selected · Enter to capture · Esc to cancel", in: ctx)
            } else {
                drawInstruction("Click a screen · Esc to cancel", in: ctx)
            }
            return
        }

        if mode == .window, let window = clickedWindow ?? hoveredWindow {
            drawWindowHighlight(window, in: ctx)
        } else if mode == .hybrid && dragStart == nil, let window = clickedWindow ?? hoveredWindow {
            drawWindowHighlight(window, in: ctx)
        }
        if mode == .window {
            drawInstruction(
                clickedWindow == nil
                    ? "Click a window · Esc to cancel"
                    : "Window selected · Enter to capture · Esc to cancel",
                in: ctx
            )
            return
        }

        if selectionRectLocal == nil, clickedWindow == nil {
            let suffix = (mode == .area || mode == .hybrid) && aspectLock != .auto
                ? " · \(aspectLock.displayName) lock"
                : ""
            let action = mode == .hybrid ? "Click a window or drag a region" : "Drag to select"
            drawInstruction("\(action) · Esc to cancel\(suffix)", in: ctx)
        }

        // Area / scrolling mode: crosshair before drag, rubber band during.
        if let rect = selectionRectLocal, dragStart != nil {
            reveal(rect, in: ctx)
            
            ctx.saveGState()
            // Soft double stroke with drop shadow
            ctx.setShadow(offset: .zero, blur: 5, color: NSColor.black.withAlphaComponent(0.4).cgColor)
            
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(rect.insetBy(dx: 0.75, dy: 0.75))
            
            ctx.setStrokeColor(AeroTheme.accentNSColor.cgColor)
            ctx.setLineWidth(1.0)
            ctx.stroke(rect)
            ctx.restoreGState()

            drawLabel(dimensionLabel(for: rect), near: rect, in: ctx)
        } else if let p = currentPoint, !(mode == .hybrid && hoveredWindow != nil) {
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

    private func drawWindowHighlight(_ window: WindowEnumerator.WindowInfo, in ctx: CGContext) {
        let rect = localRect(fromSCFrame: window.scFrame).intersection(bounds)
        guard !rect.isNull, !rect.isEmpty else { return }
        reveal(rect, in: ctx)
        ctx.setFillColor(AeroTheme.accentNSColor.withAlphaComponent(0.2).cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(AeroTheme.accentNSColor.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(rect.insetBy(dx: 1, dy: 1))
        drawLabel("\(window.appName)\(window.title.isEmpty ? "" : " — \(window.title)")", near: rect, in: ctx)
    }

    private func reveal(_ rect: CGRect, in ctx: CGContext) {
        guard freezesScreen, let frozenImage else {
            ctx.clear(rect)
            return
        }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setBlendMode(.copy)
        ctx.interpolationQuality = .none
        ctx.draw(frozenImage, in: bounds)
        ctx.restoreGState()
    }

    private func dimensionLabel(for rect: CGRect) -> String {
        let width = Int((rect.width * display.scale).rounded())
        let height = Int((rect.height * display.scale).rounded())
        if let badge = aspectLock.badgeLabel {
            return "\(width) × \(height) · \(badge)"
        }
        return "\(width) × \(height)"
    }

    private static let labelFont: NSFont = {
        if let menlo = NSFont(name: "Menlo-Bold", size: 11) { return menlo }
        return NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    }()

    private func drawLabel(_ text: String, near rect: CGRect, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont,
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 10)
        if origin.y < 4 { origin.y = rect.minY + 10 }
        origin.x = max(4, min(origin.x, bounds.width - size.width - 4))
        
        drawPill(str, at: origin, horizontalPadding: 8, verticalPadding: 3, cornerRadius: 5, in: ctx)
    }

    private func drawInstruction(_ text: String, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - size.height - 44)
        drawPill(str, at: origin, horizontalPadding: 12, verticalPadding: 4, cornerRadius: 6, in: ctx)
    }

    private func drawPill(
        _ string: NSAttributedString,
        at origin: NSPoint,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        cornerRadius: CGFloat,
        in ctx: CGContext
    ) {
        let size = string.size()
        let background = CGRect(
            x: origin.x - horizontalPadding,
            y: origin.y - verticalPadding,
            width: size.width + horizontalPadding * 2,
            height: size.height + verticalPadding * 2
        )

        ctx.saveGState()
        ctx.setFillColor(AeroTheme.overlayLabelBackground.cgColor)
        ctx.addPath(CGPath(roundedRect: background, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(CGPath(roundedRect: background.insetBy(dx: 0.25, dy: 0.25), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        ctx.strokePath()
        ctx.restoreGState()

        string.draw(at: origin)
    }
}
