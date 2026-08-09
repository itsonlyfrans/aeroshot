import AppKit
import ScreenCaptureKit

struct SelectionDragGeometry {
    static func initialRect(anchor: CGPoint, pointer: CGPoint, ratio: CGFloat?, bounds: CGRect) -> CGRect {
        let anchor = clamped(anchor, to: bounds)
        let pointer = clamped(pointer, to: bounds)
        let signX: CGFloat = pointer.x >= anchor.x ? 1 : -1
        let signY: CGFloat = pointer.y >= anchor.y ? 1 : -1
        var width = abs(pointer.x - anchor.x)
        var height = abs(pointer.y - anchor.y)

        if let ratio, ratio > 0, (width > 0 || height > 0) {
            if width / max(height, 0.001) > ratio {
                height = width / ratio
            } else {
                width = height * ratio
            }

            var scale: CGFloat = 1
            if width > 0 {
                let availableWidth = signX >= 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
                scale = min(scale, availableWidth / width)
            }
            if height > 0 {
                let availableHeight = signY >= 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
                scale = min(scale, availableHeight / height)
            }
            width *= max(0, scale)
            height *= max(0, scale)
        }

        let endpoint = CGPoint(x: anchor.x + signX * width, y: anchor.y + signY * height)
        return CGRect(x: min(anchor.x, endpoint.x),
                      y: min(anchor.y, endpoint.y),
                      width: abs(endpoint.x - anchor.x),
                      height: abs(endpoint.y - anchor.y))
    }

    static func translatedRect(originalRect: CGRect, pointerDown: CGPoint, pointer: CGPoint, bounds: CGRect) -> CGRect {
        let width = min(originalRect.width, bounds.width)
        let height = min(originalRect.height, bounds.height)
        let delta = CGPoint(x: pointer.x - pointerDown.x, y: pointer.y - pointerDown.y)
        let maxX = bounds.maxX - width
        let maxY = bounds.maxY - height
        let origin = CGPoint(
            x: min(max(originalRect.minX + delta.x, bounds.minX), maxX),
            y: min(max(originalRect.minY + delta.y, bounds.minY), maxY)
        )
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    static func anchoredSnap(
        _ rect: CGRect,
        anchor: CGPoint,
        xTargets: [CGFloat],
        yTargets: [CGFloat],
        distance: CGFloat = 8
    ) -> CGRect {
        var result = rect
        if rect.width > 0 {
            if abs(anchor.x - rect.maxX) <= 0.001,
               let target = nearest(rect.minX, targets: xTargets, distance: distance),
               target <= anchor.x {
                result = CGRect(x: target, y: result.minY, width: anchor.x - target, height: result.height)
            } else if abs(anchor.x - rect.minX) <= 0.001,
                      let target = nearest(rect.maxX, targets: xTargets, distance: distance),
                      target >= anchor.x {
                result = CGRect(x: anchor.x, y: result.minY, width: target - anchor.x, height: result.height)
            }
        }
        if rect.height > 0 {
            if abs(anchor.y - rect.maxY) <= 0.001,
               let target = nearest(rect.minY, targets: yTargets, distance: distance),
               target <= anchor.y {
                result = CGRect(x: result.minX, y: target, width: result.width, height: anchor.y - target)
            } else if abs(anchor.y - rect.minY) <= 0.001,
                      let target = nearest(rect.maxY, targets: yTargets, distance: distance),
                      target >= anchor.y {
                result = CGRect(x: result.minX, y: anchor.y, width: result.width, height: target - anchor.y)
            }
        }
        return result
    }

    private static func clamped(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private static func nearest(_ value: CGFloat, targets: [CGFloat], distance: CGFloat) -> CGFloat? {
        guard let target = targets.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(target - value) <= distance else { return nil }
        return target
    }
}

enum SelectionMarkupTool: CaseIterable {
    case region, freehand, rectangle, arrow

    var label: String {
        switch self {
        case .region: "Region"
        case .freehand: "Pen"
        case .rectangle: "Rectangle"
        case .arrow: "Arrow"
        }
    }

    var toolKind: ToolKind? {
        switch self {
        case .region: nil
        case .freehand: .freehand
        case .rectangle: .rectangle
        case .arrow: .arrow
        }
    }
}

enum SelectionMarkupGeometry {
    static func imagePoint(local: CGPoint, viewSize: CGSize, imageSize: CGSize) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        return CGPoint(
            x: local.x * imageSize.width / viewSize.width,
            y: (viewSize.height - local.y) * imageSize.height / viewSize.height
        )
    }
}

/// Per-screen selection view: dimming, rubber-band, crosshair, dimension
/// label, drag-only loupe, and window hover-highlight.
final class SelectionOverlayView: NSView, NSTextFieldDelegate {

    var onCommit: ((SelectionResult) -> Void)?
    var onCancel: (() -> Void)?
    var onSelectionBegan: (() -> Void)?
    var onIntentSelected: ((SelectionSurfaceIntent) -> Void)?
    var onAspectLockSelected: ((SelectionAspectLock) -> Void)?
    var onContextAction: ((SelectionSurfaceAction) -> Void)?
    var onSelectionMoved: ((SelectionResult) -> Void)?
    var onMarkupInteraction: (() -> Void)?

    private let display: DisplayInfo
    private let windows: [WindowEnumerator.WindowInfo]
    private let frozenImage: CGImage?
    private var mode: SelectionMode
    private var aspectLock: SelectionAspectLock
    private var freezesScreen: Bool
    private let showsContextRail: Bool
    private var allowsMarkup: Bool

    private var dragStart: NSPoint?          // view-local
    private var currentPoint: NSPoint?       // view-local selection endpoint
    private var hoverPoint: NSPoint?         // view-local pointer, independent of a retained rect
    private var hoveredWindow: WindowEnumerator.WindowInfo?
    private var clickedWindow: WindowEnumerator.WindowInfo?
    private var screenSelected = false
    private var selectionRetained = false
    private var didDrag = false
    private var trackingArea: NSTrackingArea?
    private var surfaceIntent: SelectionSurfaceIntent
    private let availableSurfaceIntents: [SelectionSurfaceIntent]
    private var intentButtonFrames: [SelectionSurfaceIntent: CGRect] = [:]
    private var actionButtonFrames: [SelectionSurfaceAction: CGRect] = [:]
    private var hoveredAction: SelectionSurfaceAction?
    private var editableDimensionFrame: CGRect = .zero
    private var dimensionEditor: NSTextField?
    private var aspectButtonFrame: CGRect = .zero
    private var pointerOverChrome = false
    private var activeResizeHandle: ResizeHandle?
    private var resizeStartRect: CGRect?
    private var movingSelection: (pointer: NSPoint, rect: CGRect)?
    private var snapGuides: [SnapGuide] = []
    private var destinationIndex = 0
    private let destinations = ["Desktop", "Clipboard only", "Downloads", "Aeroshot Library", "Ask each time"]
    private lazy var sampleBitmap: NSBitmapImageRep? = frozenImage.map(NSBitmapImageRep.init(cgImage:))
    private var accessibilityProxies: [SelectionAccessibilityButton] = []
    private var markupTool: SelectionMarkupTool = .region
    private var hoveredMarkupTool: SelectionMarkupTool?
    private var markupButtonFrames: [SelectionMarkupTool: CGRect] = [:]
    private var inProgressMarkup: Annotation?
    private lazy var markupDocument = EditorDocument(image: frozenImage ?? Self.emptyImage)

    var displayID: CGDirectDisplayID { display.displayID }
    var markupAnnotations: [Annotation] { markupDocument.annotations }

    private enum ResizeHandle: CaseIterable, Equatable {
        case northWest, north, northEast, east, southEast, south, southWest, west

        var changesMinX: Bool {
            self == .northWest || self == .southWest || self == .west
        }

        var changesMaxX: Bool {
            self == .northEast || self == .southEast || self == .east
        }

        var changesMinY: Bool {
            self == .southEast || self == .southWest || self == .south
        }

        var changesMaxY: Bool {
            self == .northWest || self == .northEast || self == .north
        }
    }

    private enum SnapGuide: Equatable {
        case vertical(CGFloat)
        case horizontal(CGFloat)
    }

    init(display: DisplayInfo,
         windows: [WindowEnumerator.WindowInfo],
         frozenImage: CGImage?,
         freezesScreen: Bool = false,
         mode: SelectionMode,
         aspectLock: SelectionAspectLock = .auto,
         availableSurfaceIntents: [SelectionSurfaceIntent] = SelectionSurfaceIntent.allCases,
         showsContextRail: Bool = true,
         allowsMarkup: Bool = false) {
        self.display = display
        self.windows = windows
        self.frozenImage = frozenImage
        self.mode = mode
        self.surfaceIntent = SelectionSurfaceIntent(mode: mode)
        self.availableSurfaceIntents = availableSurfaceIntents
        self.aspectLock = aspectLock
        self.freezesScreen = freezesScreen
        self.showsContextRail = showsContextRail
        self.allowsMarkup = allowsMarkup
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func setAspectLock(_ lock: SelectionAspectLock) {
        aspectLock = lock
        constrainSelectionToAspect()
        needsDisplay = true
    }

    func setFreezesScreen(_ enabled: Bool) {
        freezesScreen = enabled
        needsDisplay = true
    }

    func setAllowsMarkup(_ enabled: Bool) {
        allowsMarkup = enabled
        if !enabled {
            markupTool = .region
            _ = cancelInProgressMarkup()
        }
        needsDisplay = true
    }

    func setMode(_ newMode: SelectionMode) {
        dimensionEditor?.removeFromSuperview()
        dimensionEditor = nil
        mode = newMode
        surfaceIntent = SelectionSurfaceIntent(mode: newMode)
        dragStart = nil
        currentPoint = nil
        hoverPoint = nil
        hoveredWindow = nil
        clickedWindow = nil
        screenSelected = false
        selectionRetained = false
        didDrag = false
        activeResizeHandle = nil
        resizeStartRect = nil
        movingSelection = nil
        snapGuides.removeAll(keepingCapacity: true)
        needsDisplay = true
        activateSelectionCursor()
    }

    func setSurfaceIntent(_ intent: SelectionSurfaceIntent) {
        surfaceIntent = intent
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityLabel() -> String? { "Screen capture selection" }

    override func accessibilityChildren() -> [Any] {
        refreshAccessibilityProxies()
        return accessibilityProxies
    }

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

    private func clampedPoint(_ point: NSPoint) -> NSPoint {
        NSPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private var markupImageSize: CGSize {
        if let frozenImage {
            return CGSize(width: frozenImage.width, height: frozenImage.height)
        }
        return CGSize(width: bounds.width * display.scale, height: bounds.height * display.scale)
    }

    private func markupPoint(for local: CGPoint) -> CGPoint {
        SelectionMarkupGeometry.imagePoint(local: local, viewSize: bounds.size, imageSize: markupImageSize)
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
        let point = clampedPoint(local)
        hoverPoint = point
        guard dragStart == nil else { return }
        currentPoint = point
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
        let previousAction = hoveredAction
        let previousChrome = pointerOverChrome
        hoverPoint = clampedPoint(local)
        let previousMarkupTool = hoveredMarkupTool
        hoveredMarkupTool = hitMarkupTool(at: local)
        hoveredAction = hitAction(at: local)
        pointerOverChrome = hoveredMarkupTool != nil
            || hitIntent(at: local) != nil
            || hoveredAction != nil
            || aspectButtonFrame.contains(local)
        if previousAction != hoveredAction || previousMarkupTool != hoveredMarkupTool || previousChrome != pointerOverChrome {
            needsDisplay = true
        }
        if pointerOverChrome {
            NSCursor.pointingHand.set()
            if dragStart == nil {
                currentPoint = clampedPoint(local)
                needsDisplay = true
            }
            return
        }
        if selectionRectLocal != nil, resizeHandle(at: local) != nil {
            NSCursor.crosshair.set()
            return
        }
        if selectionRetained, let rect = selectionRectLocal, rect.contains(local) {
            NSCursor.openHand.set()
            return
        }
        updatePointer(local: local, screenPoint: NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        activateSelectionCursor()
        let local = clampedPoint(convert(event.locationInWindow, from: nil))
        hoverPoint = local
        pointerOverChrome = false
        if let tool = hitMarkupTool(at: local) {
            markupTool = tool
            onMarkupInteraction?()
            pointerOverChrome = true
            needsDisplay = true
            return
        }
        if let intent = hitIntent(at: local) {
            surfaceIntent = intent
            onIntentSelected?(intent)
            pointerOverChrome = true
            needsDisplay = true
            return
        }
        if aspectButtonFrame.contains(local) {
            let options = SelectionAspectLock.allCases
            let index = options.firstIndex(of: aspectLock) ?? 0
            onAspectLockSelected?(options[(index + 1) % options.count])
            pointerOverChrome = true
            return
        }
        if selectionRetained, editableDimensionFrame.contains(local) {
            beginDimensionEdit()
            pointerOverChrome = true
            return
        }
        if let action = hitAction(at: local) {
            if action == .destination {
                destinationIndex = (destinationIndex + 1) % destinations.count
                pointerOverChrome = true
                needsDisplay = true
                onContextAction?(action)
                return
            }
            onContextAction?(action)
            pointerOverChrome = true
            return
        }
        if allowsMarkup, (mode == .area || mode == .hybrid), let toolKind = markupTool.toolKind,
           let tool = ToolFactory.tool(for: toolKind) {
            onMarkupInteraction?()
            inProgressMarkup = tool.begin(at: markupPoint(for: local), style: ToolStyle(), document: markupDocument)
            needsDisplay = true
            return
        }
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
        if selectionRetained, let rect = selectionRectLocal, rect.contains(local), resizeHandle(at: local) == nil {
            movingSelection = (local, rect)
            didDrag = false
            snapGuides.removeAll(keepingCapacity: true)
            needsDisplay = true
            return
        }
        if let handle = resizeHandle(at: local), let rect = selectionRectLocal {
            activeResizeHandle = handle
            resizeStartRect = rect
            didDrag = false
            snapGuides.removeAll(keepingCapacity: true)
            needsDisplay = true
            return
        }
        clickedWindow = mode == .hybrid
            ? WindowEnumerator.frontmostWindow(at: NSEvent.mouseLocation, candidates: windows)
            : nil
        selectionRetained = false
        didDrag = false
        dragStart = local
        currentPoint = local
        onSelectionBegan?()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        activateSelectionCursor()
        guard mode != .window, mode != .screen else { return }
        let point = clampedPoint(convert(event.locationInWindow, from: nil))
        hoverPoint = point
        if var annotation = inProgressMarkup, let toolKind = markupTool.toolKind,
           let tool = ToolFactory.tool(for: toolKind) {
            tool.update(&annotation, to: markupPoint(for: point))
            inProgressMarkup = annotation
            needsDisplay = true
            return
        }
        if let movingSelection {
            let delta = CGPoint(x: point.x - movingSelection.pointer.x,
                                y: point.y - movingSelection.pointer.y)
            let proposed = SelectionDragGeometry.translatedRect(
                originalRect: movingSelection.rect,
                pointerDown: movingSelection.pointer,
                pointer: point,
                bounds: bounds
            )
            let snapped = proposed
            guard snapped.width >= 2, snapped.height >= 2 else { return }
            didDrag = didDrag || abs(delta.x) >= 2 || abs(delta.y) >= 2
            NSCursor.closedHand.set()
            dragStart = snapped.origin
            currentPoint = NSPoint(x: snapped.maxX, y: snapped.maxY)
            needsDisplay = true
            return
        }
        if let handle = activeResizeHandle, let startRect = resizeStartRect {
            didDrag = true
            resizeSelection(startRect, handle: handle, toward: point)
            needsDisplay = true
            return
        }
        if let start = dragStart {
            didDrag = didDrag || abs(point.x - start.x) >= 2 || abs(point.y - start.y) >= 2
        }
        if let start = dragStart, aspectLock.ratio != nil {
            let rect = SelectionDragGeometry.initialRect(
                anchor: start,
                pointer: point,
                ratio: aspectLock.ratio!,
                bounds: bounds
            )
            let snapped = snapSelection(rect, moving: nil, anchoredAt: start)
            currentPoint = movingEndpoint(in: snapped, anchoredAt: start)
        } else if let start = dragStart {
            let rect = SelectionDragGeometry.initialRect(
                anchor: start,
                pointer: point,
                ratio: nil,
                bounds: bounds
            )
            let snapped = snapSelection(rect, moving: nil, anchoredAt: start)
            currentPoint = movingEndpoint(in: snapped, anchoredAt: start)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode != .window, mode != .screen else { return }
        hoverPoint = clampedPoint(convert(event.locationInWindow, from: nil))
        if let annotation = inProgressMarkup, let toolKind = markupTool.toolKind,
           let tool = ToolFactory.tool(for: toolKind) {
            if tool.shouldCommit(annotation) {
                markupDocument.perform(AddAnnotationCommand(annotation: annotation))
            }
            inProgressMarkup = nil
            needsDisplay = true
            return
        }
        if activeResizeHandle != nil {
            activeResizeHandle = nil
            resizeStartRect = nil
            guard let rect = selectionRectLocal, rect.width >= 2, rect.height >= 2 else {
                didDrag = false
                snapGuides.removeAll(keepingCapacity: true)
                needsDisplay = true
                return
            }
            snapGuides.removeAll(keepingCapacity: true)
            didDrag = false
            commitArea(rect)
            return
        }
        if movingSelection != nil {
            movingSelection = nil
            snapGuides.removeAll(keepingCapacity: true)
            if didDrag, let rect = selectionRectLocal, rect.width >= 2, rect.height >= 2 {
                onSelectionMoved?(.area(cocoaRect: globalRect(for: rect), display: display))
            }
            didDrag = false
            needsDisplay = true
            return
        }
        if mode == .hybrid, !didDrag, let clickedWindow {
            onCommit?(.window(clickedWindow))
            return
        }
        guard let rect = selectionRectLocal, rect.width >= 2, rect.height >= 2 else {
            dragStart = nil
            clickedWindow = nil
            didDrag = false
            snapGuides.removeAll(keepingCapacity: true)
            needsDisplay = true
            return
        }
        snapGuides.removeAll(keepingCapacity: true)
        didDrag = false
        commitArea(rect)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            if !cancelInProgressMarkup() { onCancel?() }
        case 6 where event.modifierFlags.contains(.command): // Cmd-Z
            _ = performMarkupUndo(redo: event.modifierFlags.contains(.shift))
        case 36, 76: // Return / Enter — commit current selection if any
            if selectionRetained {
                onContextAction?(.copy)
            } else if let rect = selectionRectLocal, rect.width >= 2, rect.height >= 2 {
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

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let editor = dimensionEditor else { return }
        let parts = editor.stringValue
            .replacingOccurrences(of: "×", with: "x")
            .split(separator: "x", maxSplits: 1, omittingEmptySubsequences: true)
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2, parts[0] >= 2, parts[1] >= 2,
           let rect = selectionRectLocal ?? (screenSelected ? bounds : nil) {
            let proposed = CGRect(x: rect.minX,
                                  y: rect.minY,
                                  width: CGFloat(parts[0]) / display.scale,
                                  height: CGFloat(parts[1]) / display.scale)
                .intersection(bounds)
            if proposed.width >= 2, proposed.height >= 2 {
                dragStart = proposed.origin
                currentPoint = NSPoint(x: proposed.maxX, y: proposed.maxY)
                clampSelectionToBounds()
                if let updated = selectionRectLocal {
                    onSelectionMoved?(.area(cocoaRect: globalRect(for: updated), display: display))
                }
            }
        }
        editor.removeFromSuperview()
        dimensionEditor = nil
        editableDimensionFrame = .zero
        needsDisplay = true
    }

    private func beginDimensionEdit() {
        guard dimensionEditor == nil,
              let rect = selectionRectLocal ?? (screenSelected ? bounds : nil) else { return }
        let field = NSTextField(frame: editableDimensionFrame.insetBy(dx: 4, dy: 2))
        field.stringValue = "\(Int((rect.width * display.scale).rounded())) × \(Int((rect.height * display.scale).rounded()))"
        field.font = Self.labelFont
        field.alignment = .center
        field.textColor = .white
        field.drawsBackground = true
        field.backgroundColor = AeroTheme.overlayLabelBackground
        field.isBordered = false
        field.focusRingType = .none
        field.delegate = self
        addSubview(field)
        dimensionEditor = field
        field.selectText(nil)
        window?.makeFirstResponder(field)
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
            currentPoint = clampedPoint(point)
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
        if selectionRetained, let rect = selectionRectLocal, rect.width >= 2, rect.height >= 2 {
            onSelectionMoved?(.area(cocoaRect: globalRect(for: rect), display: display))
        }
        needsDisplay = true
    }

    private func clampSelectionToBounds() {
        guard var start = dragStart, var end = currentPoint else { return }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        var shiftX: CGFloat = 0
        var shiftY: CGFloat = 0
        if rect.minX < bounds.minX { shiftX = bounds.minX - rect.minX }
        if rect.maxX > bounds.maxX { shiftX = bounds.maxX - rect.maxX }
        if rect.minY < bounds.minY { shiftY = bounds.minY - rect.minY }
        if rect.maxY > bounds.maxY { shiftY = bounds.maxY - rect.maxY }
        guard shiftX != 0 || shiftY != 0 else { return }
        start.x += shiftX
        start.y += shiftY
        end.x += shiftX
        end.y += shiftY
        dragStart = start
        currentPoint = end
    }

    private func constrainSelectionToAspect() {
        guard let ratio = aspectLock.ratio,
              let start = dragStart,
              let end = currentPoint else { return }
        let rect = SelectionDragGeometry.initialRect(
            anchor: start,
            pointer: end,
            ratio: ratio,
            bounds: bounds
        )
        dragStart = start
        currentPoint = movingEndpoint(in: rect, anchoredAt: start)
        snapGuides.removeAll(keepingCapacity: true)
    }

    private func resizeSelection(_ startRect: CGRect, handle: ResizeHandle, toward point: NSPoint) {
        let point = clampedPoint(point)
        var proposed = startRect
        var minX = startRect.minX
        var maxX = startRect.maxX
        var minY = startRect.minY
        var maxY = startRect.maxY

        if handle.changesMinX { minX = min(point.x, maxX - 2) }
        if handle.changesMaxX { maxX = max(point.x, minX + 2) }
        if handle.changesMinY { minY = min(point.y, maxY - 2) }
        if handle.changesMaxY { maxY = max(point.y, minY + 2) }
        proposed = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        if let ratio = aspectLock.ratio {
            let anchor: CGPoint
            switch handle {
            case .northWest: anchor = CGPoint(x: startRect.maxX, y: startRect.minY)
            case .north: anchor = CGPoint(x: startRect.midX, y: startRect.minY)
            case .northEast: anchor = CGPoint(x: startRect.minX, y: startRect.minY)
            case .east: anchor = CGPoint(x: startRect.minX, y: startRect.midY)
            case .southEast: anchor = CGPoint(x: startRect.minX, y: startRect.maxY)
            case .south: anchor = CGPoint(x: startRect.midX, y: startRect.maxY)
            case .southWest: anchor = CGPoint(x: startRect.maxX, y: startRect.maxY)
            case .west: anchor = CGPoint(x: startRect.maxX, y: startRect.midY)
            }
            let constrained = SelectionAspectLock.constrainedRect(
                origin: anchor,
                current: point,
                ratio: ratio,
                bounds: bounds
            )
            proposed = CGRect(
                x: min(constrained.origin.x, constrained.current.x),
                y: min(constrained.origin.y, constrained.current.y),
                width: abs(constrained.current.x - constrained.origin.x),
                height: abs(constrained.current.y - constrained.origin.y)
            )
        }

        proposed = snapSelection(proposed, moving: handle)
        proposed = proposed.intersection(bounds)
        guard proposed.width >= 2, proposed.height >= 2 else { return }
        dragStart = proposed.origin
        currentPoint = clampedPoint(NSPoint(x: proposed.maxX, y: proposed.maxY))
    }

    private func resizeHandle(at point: NSPoint) -> ResizeHandle? {
        guard let rect = selectionRectLocal, rect.width >= 8, rect.height >= 8 else { return nil }
        let hitRadius: CGFloat = 10
        let locations: [(ResizeHandle, CGPoint)] = [
            (.northWest, CGPoint(x: rect.minX, y: rect.maxY)),
            (.north, CGPoint(x: rect.midX, y: rect.maxY)),
            (.northEast, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.east, CGPoint(x: rect.maxX, y: rect.midY)),
            (.southEast, CGPoint(x: rect.maxX, y: rect.minY)),
            (.south, CGPoint(x: rect.midX, y: rect.minY)),
            (.southWest, CGPoint(x: rect.minX, y: rect.minY)),
            (.west, CGPoint(x: rect.minX, y: rect.midY)),
        ]
        return locations.first { hypot($0.1.x - point.x, $0.1.y - point.y) <= hitRadius }?.0
    }

    private func snapSelection(_ rect: CGRect, moving handle: ResizeHandle?, anchoredAt anchor: CGPoint? = nil) -> CGRect {
        let snapDistance: CGFloat = 8
        let xTargets: [CGFloat] = [bounds.minX, bounds.midX, bounds.maxX]
        let yTargets: [CGFloat] = [bounds.minY, bounds.midY, bounds.maxY]
        if let anchor {
            let snapped = SelectionDragGeometry.anchoredSnap(
                rect,
                anchor: anchor,
                xTargets: xTargets,
                yTargets: yTargets,
                distance: snapDistance
            )
            var guides: [SnapGuide] = []
            if snapped.minX != rect.minX || snapped.maxX != rect.maxX {
                guides.append(.vertical(abs(anchor.x - rect.minX) <= 0.001 ? snapped.maxX : snapped.minX))
            }
            if snapped.minY != rect.minY || snapped.maxY != rect.maxY {
                guides.append(.horizontal(abs(anchor.y - rect.minY) <= 0.001 ? snapped.maxY : snapped.minY))
            }
            snapGuides = guides
            return snapped
        }

        var result = rect
        var guides: [SnapGuide] = []

        func nearest(_ value: CGFloat, targets: [CGFloat]) -> CGFloat? {
            guard let target = targets.min(by: { abs($0 - value) < abs($1 - value) }),
                  abs(target - value) <= snapDistance else { return nil }
            return target
        }

        let allowMinX = result.width > 0 && (handle == nil || handle?.changesMinX == true)
        let allowMaxX = result.width > 0 && (handle == nil || handle?.changesMaxX == true)
        let allowMinY = result.height > 0 && (handle == nil || handle?.changesMinY == true)
        let allowMaxY = result.height > 0 && (handle == nil || handle?.changesMaxY == true)
        if allowMinX, let target = nearest(result.minX, targets: xTargets) {
            result.origin.x = target
            guides.append(.vertical(target))
        } else if allowMaxX, let target = nearest(result.maxX, targets: xTargets) {
            result.origin.x = target - result.width
            guides.append(.vertical(target))
        }
        if allowMinY, let target = nearest(result.minY, targets: yTargets) {
            result.origin.y = target
            guides.append(.horizontal(target))
        } else if allowMaxY, let target = nearest(result.maxY, targets: yTargets) {
            result.origin.y = target - result.height
            guides.append(.horizontal(target))
        }
        snapGuides = guides
        return result
    }

    private func movingEndpoint(in rect: CGRect, anchoredAt anchor: CGPoint) -> NSPoint {
        let x = abs(anchor.x - rect.minX) <= 0.001 ? rect.maxX : rect.minX
        let y = abs(anchor.y - rect.minY) <= 0.001 ? rect.maxY : rect.minY
        return NSPoint(x: x, y: y)
    }

    private func commitArea(_ localRect: CGRect) {
        let bounded = localRect.standardized.intersection(bounds)
        guard !bounded.isNull, bounded.width >= 2, bounded.height >= 2 else { return }
        // Snap to whole points so pixels align at any scale.
        let snapped = CGRect(x: bounded.origin.x.rounded(.down),
                             y: bounded.origin.y.rounded(.down),
                             width: bounded.width.rounded(),
                             height: bounded.height.rounded())
        guard let window else { return }
        let inWindow = convert(snapped, to: nil)
        let global = window.convertToScreen(inWindow)
        onCommit?(.area(cocoaRect: global, display: display))
    }

    func retainSelection(_ result: SelectionResult) {
        dragStart = nil
        currentPoint = nil
        hoverPoint = nil
        clickedWindow = nil
        hoveredWindow = nil
        screenSelected = false
        selectionRetained = false
        didDrag = false
        activeResizeHandle = nil
        resizeStartRect = nil
        movingSelection = nil
        snapGuides.removeAll(keepingCapacity: true)

        switch result {
        case .area(let rect, let selectedDisplay) where selectedDisplay.displayID == display.displayID:
            let local = localRect(fromGlobalCocoa: rect).standardized.intersection(bounds)
            guard !local.isNull, local.width >= 2, local.height >= 2 else { break }
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

    @discardableResult
    func cancelInProgressMarkup() -> Bool {
        guard inProgressMarkup != nil else { return false }
        inProgressMarkup = nil
        needsDisplay = true
        return true
    }

    @discardableResult
    func performMarkupUndo(redo: Bool) -> Bool {
        guard allowsMarkup, mode == .area || mode == .hybrid else { return false }
        if redo {
            guard markupDocument.undoStack.canRedo else { return false }
            markupDocument.redo()
        } else {
            guard markupDocument.undoStack.canUndo else { return false }
            markupDocument.undo()
        }
        needsDisplay = true
        return true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        defer { refreshAccessibilityProxies() }

        intentButtonFrames.removeAll(keepingCapacity: true)
        actionButtonFrames.removeAll(keepingCapacity: true)
        aspectButtonFrame = .zero
        editableDimensionFrame = .zero

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
                drawSelectionMarks(around: bounds.insetBy(dx: 2, dy: 2), in: ctx)
                drawLabel(dimensionLabel(for: bounds), near: bounds.insetBy(dx: 2, dy: 2), in: ctx)
                drawContextRail(for: .screen(display), in: ctx)
            } else {
                drawInstruction("Click a screen · Esc to cancel", in: ctx)
            }
            drawIntentRail(in: ctx)
            return
        }

        if mode == .window, let window = clickedWindow ?? hoveredWindow {
            drawWindowHighlight(window, in: ctx)
        } else if mode == .hybrid && dragStart == nil, let window = clickedWindow ?? hoveredWindow {
            drawWindowHighlight(window, in: ctx)
            if selectionRetained, let clickedWindow {
                drawContextRail(for: .window(clickedWindow), in: ctx)
            }
        }
        if mode == .window {
            if clickedWindow == nil {
                drawInstruction("Click a window · Esc to cancel", in: ctx)
            }
            if selectionRetained, let window = clickedWindow {
                drawContextRail(for: .window(window), in: ctx)
            }
            drawIntentRail(in: ctx)
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

            drawSelectionMarks(around: rect, in: ctx)
            let labelFrame = drawLabel(dimensionLabel(for: rect), near: rect, in: ctx)
            if selectionRetained { editableDimensionFrame = labelFrame }
            drawOrigin(for: rect, in: ctx)
            drawResizeHandles(around: rect, in: ctx)
            drawSnapGuides(in: ctx)
            if selectionRetained {
                drawContextRail(for: .area(cocoaRect: globalRect(for: rect), display: display), in: ctx)
            }
        } else if let p = currentPoint, !(mode == .hybrid && hoveredWindow != nil) {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(0.75)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.strokeLineSegments(between: [CGPoint(x: 0, y: p.y), CGPoint(x: bounds.width, y: p.y)])
            ctx.strokeLineSegments(between: [CGPoint(x: p.x, y: 0), CGPoint(x: p.x, y: bounds.height)])
            ctx.restoreGState()
            
        }

        drawMarkupAnnotations(in: ctx)
        drawMarkupToolbar(in: ctx)
        drawIntentRail(in: ctx)
        if let p = hoverPoint ?? currentPoint, !pointerOverChrome {
            if didDrag, dragStart != nil, !selectionRetained {
                drawLoupe(at: p, in: ctx)
            }
            if !selectionRetained, selectionRectLocal == nil {
                drawModeHint(at: p, in: ctx)
            }
        }
    }

    private func globalRect(for localRect: CGRect) -> CGRect {
        guard let window else { return localRect }
        return window.convertToScreen(convert(localRect, to: nil))
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
        drawSelectionMarks(around: rect, in: ctx)
        let dimensions = dimensionLabel(for: rect)
        drawLabel("\(window.appName)\(window.title.isEmpty ? "" : " — \(window.title)") · \(dimensions)", near: rect, in: ctx)
        drawOrigin(for: rect, in: ctx)
    }

    private func drawSelectionMarks(around rect: CGRect, in ctx: CGContext) {
        guard rect.width >= 24, rect.height >= 24 else { return }
        let accent = AeroTheme.accentNSColor.cgColor
        let length: CGFloat = 11
        let lineWidth: CGFloat = 2.5
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: length, y: 0), CGPoint(x: 0, y: length)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: -length, y: 0), CGPoint(x: 0, y: length)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: length, y: 0), CGPoint(x: 0, y: -length)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: -length, y: 0), CGPoint(x: 0, y: -length)),
        ]

        ctx.saveGState()
        ctx.setStrokeColor(accent)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.square)
        for (origin, horizontal, vertical) in corners {
            ctx.move(to: CGPoint(x: origin.x + horizontal.x, y: origin.y + horizontal.y))
            ctx.addLine(to: origin)
            ctx.addLine(to: CGPoint(x: origin.x + vertical.x, y: origin.y + vertical.y))
        }
        ctx.strokePath()

        ctx.setStrokeColor(AeroTheme.accentNSColor.withAlphaComponent(0.22).cgColor)
        ctx.setLineWidth(0.75)
        for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
            let x = rect.minX + rect.width * fraction
            let y = rect.minY + rect.height * fraction
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawResizeHandles(around rect: CGRect, in ctx: CGContext) {
        guard rect.width >= 14, rect.height >= 14 else { return }
        let handleSize: CGFloat = 8
        let points: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
        ]
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 4, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        for point in points {
            let handle = CGRect(x: point.x - handleSize / 2,
                                y: point.y - handleSize / 2,
                                width: handleSize,
                                height: handleSize)
            ctx.setFillColor(AeroTheme.accentNSColor.cgColor)
            let fillPath = CGPath(roundedRect: handle, cornerWidth: 2, cornerHeight: 2, transform: nil)
            ctx.addPath(fillPath)
            ctx.fillPath()
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(0.75)
            let strokePath = CGPath(roundedRect: handle.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            ctx.addPath(strokePath)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private func drawSnapGuides(in ctx: CGContext) {
        guard !snapGuides.isEmpty else { return }
        ctx.saveGState()
        ctx.setStrokeColor(AeroTheme.accentNSColor.withAlphaComponent(0.72).cgColor)
        ctx.setLineWidth(0.75)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        for guide in snapGuides {
            switch guide {
            case .vertical(let x):
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: bounds.height))
            case .horizontal(let y):
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: bounds.width, y: y))
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawIntentRail(in ctx: CGContext) {
        let intents = availableSurfaceIntents
        guard !intents.isEmpty else { return }
        let buttonWidth: CGFloat = 73
        let buttonHeight: CGFloat = 38
        let gap: CGFloat = 3
        let inset: CGFloat = 6
        let ratioWidth: CGFloat = 82
        let width = CGFloat(intents.count) * buttonWidth + CGFloat(intents.count) * gap
            + ratioWidth + inset * 2
        let frame = CGRect(
            x: max(12, (bounds.width - width) / 2),
            y: 28,
            width: min(width, bounds.width - 24),
            height: buttonHeight + inset * 2
        )
        drawChrome(frame, radius: 15, in: ctx)

        var x = frame.minX + inset
        for intent in intents {
            let button = CGRect(x: x, y: frame.minY + inset, width: buttonWidth, height: buttonHeight)
            intentButtonFrames[intent] = button
            let selected = intent == surfaceIntent
            if selected {
                ctx.setFillColor(AeroTheme.accentNSColor.withAlphaComponent(0.16).cgColor)
                ctx.addPath(CGPath(roundedRect: button, cornerWidth: 9, cornerHeight: 9, transform: nil))
                ctx.fillPath()
            }
            drawCentered("\(intent.key)  \(intent.symbol) \(intent.title)", in: button,
                         font: NSFont.systemFont(ofSize: 10.5, weight: selected ? .semibold : .medium),
                         color: selected ? AeroTheme.accentNSColor : NSColor.white.withAlphaComponent(0.72))
            x += buttonWidth + gap
        }

        let ratioButton = CGRect(x: min(frame.maxX - inset - ratioWidth, x),
                                 y: frame.minY + inset,
                                 width: ratioWidth,
                                 height: buttonHeight)
        aspectButtonFrame = ratioButton
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.06).cgColor)
        ctx.addPath(CGPath(roundedRect: ratioButton, cornerWidth: 9, cornerHeight: 9, transform: nil))
        ctx.fillPath()
        drawCentered("⛓  \(aspectLock.displayName)", in: ratioButton,
                     font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
                     color: aspectLock == .auto ? NSColor.white.withAlphaComponent(0.72) : AeroTheme.accentNSColor)
    }

    private func drawMarkupAnnotations(in ctx: CGContext) {
        let annotations = markupDocument.annotations + (inProgressMarkup.map { [$0] } ?? [])
        guard !annotations.isEmpty, markupImageSize.width > 0, markupImageSize.height > 0 else { return }
        ctx.saveGState()
        ctx.scaleBy(x: bounds.width / markupImageSize.width, y: bounds.height / markupImageSize.height)
        AnnotationRenderer.flip(context: ctx, height: markupImageSize.height)
        for annotation in annotations {
            AnnotationRenderer.draw(annotation, in: ctx)
        }
        ctx.restoreGState()
    }

    private func drawMarkupToolbar(in ctx: CGContext) {
        markupButtonFrames.removeAll(keepingCapacity: true)
        guard allowsMarkup, mode == .area || mode == .hybrid else { return }
        let buttonSize = CGSize(width: 78, height: 38)
        let gap: CGFloat = 3
        let inset: CGFloat = 6
        let width = CGFloat(SelectionMarkupTool.allCases.count) * buttonSize.width
            + CGFloat(SelectionMarkupTool.allCases.count - 1) * gap + inset * 2
        let frame = CGRect(x: (bounds.width - width) / 2, y: bounds.height - buttonSize.height - 28,
                           width: width, height: buttonSize.height + inset * 2)
        drawChrome(frame, radius: 14, in: ctx)
        for (index, tool) in SelectionMarkupTool.allCases.enumerated() {
            let button = CGRect(x: frame.minX + inset + CGFloat(index) * (buttonSize.width + gap),
                                y: frame.minY + inset, width: buttonSize.width, height: buttonSize.height)
            markupButtonFrames[tool] = button
            if tool == markupTool {
                ctx.setFillColor(AeroTheme.accentNSColor.withAlphaComponent(0.22).cgColor)
                ctx.addPath(CGPath(roundedRect: button, cornerWidth: 9, cornerHeight: 9, transform: nil))
                ctx.fillPath()
            } else if tool == hoveredMarkupTool {
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.09).cgColor)
                ctx.addPath(CGPath(roundedRect: button, cornerWidth: 9, cornerHeight: 9, transform: nil))
                ctx.fillPath()
            }
            drawCentered(tool.label, in: button,
                         font: NSFont.systemFont(ofSize: 11, weight: tool == markupTool ? .semibold : .medium),
                         color: tool == markupTool ? AeroTheme.accentNSColor : NSColor.white.withAlphaComponent(0.8))
        }
    }


    private func drawModeHint(at point: NSPoint, in ctx: CGContext) {
        let label: String
        switch mode {
        case .hybrid: label = "Area · drag or window"
        case .area: label = "Area · drag to select"
        case .window: label = "Window · click to select"
        case .screen: label = "Screen · click to select"
        case .scrolling: label = "Scroll · drag a region"
        }
        let text = NSAttributedString(string: label,
                                      attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium),
                                                   .foregroundColor: NSColor.white.withAlphaComponent(0.82)])
        let size = text.size()
        var origin = CGPoint(x: point.x + 15, y: point.y + 12)
        if origin.x + size.width + 14 > bounds.width { origin.x = point.x - size.width - 22 }
        if origin.y + size.height + 8 > bounds.height { origin.y = point.y - size.height - 18 }
        drawPill(text, at: origin, horizontalPadding: 7, verticalPadding: 3, cornerRadius: 5, in: ctx)
    }

    private func drawLoupe(at point: NSPoint, in ctx: CGContext) {
        guard didDrag, dragStart != nil, mode != .window, mode != .screen else { return }
        let size: CGFloat = 132
        var origin = CGPoint(x: point.x + 22, y: point.y + 22)
        if origin.x + size > bounds.width - 8 { origin.x = point.x - size - 22 }
        if origin.y + size > bounds.height - 8 { origin.y = point.y - size - 22 }
        origin.x = min(max(8, origin.x), max(8, bounds.width - size - 8))
        origin.y = min(max(8, origin.y), max(8, bounds.height - size - 8))
        let loupe = CGRect(origin: origin, size: CGSize(width: size, height: size))
        let clip = CGPath(ellipseIn: loupe, transform: nil)

        ctx.saveGState()
        ctx.addPath(clip)
        ctx.clip()
        ctx.setFillColor(NSColor(calibratedWhite: 0.08, alpha: 0.98).cgColor)
        ctx.fill(loupe)
        if let frozenImage {
            let samplePixel = CGPoint(x: point.x * display.scale,
                                      y: (bounds.height - point.y) * display.scale)
            let side = size / 8 * display.scale
            let raw = CGRect(x: samplePixel.x - side / 2, y: samplePixel.y - side / 2,
                             width: side, height: side)
            let imageBounds = CGRect(x: 0, y: 0, width: frozenImage.width, height: frozenImage.height)
            let sample = raw.intersection(imageBounds)
            if !sample.isNull, !sample.isEmpty, let cropped = frozenImage.cropping(to: sample.integral) {
                ctx.interpolationQuality = .none
                ctx.draw(cropped, in: loupe)
            }
        }
        ctx.setStrokeColor(AeroTheme.accentNSColor.withAlphaComponent(0.78).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: loupe.midX, y: loupe.minY))
        ctx.addLine(to: CGPoint(x: loupe.midX, y: loupe.maxY))
        ctx.move(to: CGPoint(x: loupe.minX, y: loupe.midY))
        ctx.addLine(to: CGPoint(x: loupe.maxX, y: loupe.midY))
        ctx.strokePath()
        ctx.restoreGState()

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(2)
        ctx.addPath(clip)
        ctx.strokePath()

        let pixelsX = Int((point.x * display.scale).rounded())
        let pixelsY = Int(((bounds.height - point.y) * display.scale).rounded())
        let metadata = "\(sampledHex(at: point))  ·  \(pixelsX), \(pixelsY)"
        let string = NSAttributedString(string: metadata,
                                         attributes: [.font: Self.labelFont,
                                                      .foregroundColor: AeroTheme.accentNSColor])
        let textSize = string.size()
        var textOrigin = CGPoint(x: loupe.midX - textSize.width / 2,
                                 y: loupe.minY - textSize.height - 7)
        if textOrigin.y < 4 { textOrigin.y = loupe.maxY + 6 }
        drawPill(string, at: textOrigin, horizontalPadding: 7, verticalPadding: 3, cornerRadius: 5, in: ctx)
    }

    private func sampledHex(at point: NSPoint) -> String {
        guard let sampleBitmap else { return "#———" }
        let x = min(max(0, Int((point.x * display.scale).rounded())), sampleBitmap.pixelsWide - 1)
        let y = min(max(0, Int(((bounds.height - point.y) * display.scale).rounded())), sampleBitmap.pixelsHigh - 1)
        guard let color = sampleBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return "#———" }
        return String(format: "#%02X%02X%02X",
                      Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()),
                      Int((color.blueComponent * 255).rounded()))
    }

    private func drawContextRail(for selection: SelectionResult, in ctx: CGContext) {
        guard showsContextRail, selectionRetained else { return }
        var actions: [SelectionSurfaceAction] = [.copy, .save, .destination, .annotate, .pin, .shareSafe]
        if case .area = selection { actions.append(.grabText) }
        actions += [.record, .dismiss]

        let afterCapture = (NSApp.delegate as? AppDelegate)?.appState.settings.openEditorAfterCapture == true
        let widths: [SelectionSurfaceAction: CGFloat] = [
            .copy: afterCapture ? 126 : 100, .save: 68, .destination: 108, .annotate: 90, .pin: 58,
            .shareSafe: 96, .grabText: 92, .record: 82, .dismiss: 38,
        ]
        let gap: CGFloat = 2
        let inset: CGFloat = 6
        let dividerCount = 2
        let dividerWidth: CGFloat = 11
        let railWidth = actions.reduce(0) { $0 + (widths[$1] ?? 76) }
            + CGFloat(actions.count - 1) * gap
            + CGFloat(dividerCount) * dividerWidth
            + inset * 2
        let height: CGFloat = 46
        let target: CGRect
        switch selection {
        case .area(let global, _): target = localRect(fromGlobalCocoa: global)
        case .window(let window): target = localRect(fromSCFrame: window.scFrame)
        case .screen: target = bounds
        }
        let idealX = target.midX - railWidth / 2
        let x = max(10, min(idealX, bounds.width - railWidth - 10))
        let y = target.minY >= 92
            ? target.minY - height - 14
            : min(bounds.height - height - 14, target.maxY + 14)
        let frame = CGRect(x: x, y: y, width: railWidth, height: height)
        drawChrome(frame, radius: 12, in: ctx)

        var buttonX = frame.minX + inset
        for action in actions {
            let width = widths[action] ?? 76
            let button = CGRect(x: buttonX, y: frame.minY + 6, width: width, height: 34)
            actionButtonFrames[action] = button
            if action == .copy {
                ctx.setFillColor(AeroTheme.accentNSColor.cgColor)
                ctx.addPath(CGPath(roundedRect: button, cornerWidth: 9, cornerHeight: 9, transform: nil))
                ctx.fillPath()
            } else if hoveredAction == action {
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
                ctx.addPath(CGPath(roundedRect: button, cornerWidth: 9, cornerHeight: 9, transform: nil))
                ctx.fillPath()
            }
            let label: String
            if action == .destination {
                label = destinations[destinationIndex] + "  ▾"
            } else if action == .copy, afterCapture {
                label = "⧉  Copy  → ✎  ⏎"
            } else {
                label = action.label
            }
            drawCentered(label, in: button,
                         font: NSFont.systemFont(ofSize: 11.5, weight: action == .copy ? .semibold : .medium),
                         color: action == .copy ? NSColor(calibratedWhite: 0.07, alpha: 1) : .white)
            buttonX += width + gap
            let shouldDivide = action == .destination
                || action == .grabText
                || (action == .shareSafe && !actions.contains(.grabText))
            if shouldDivide {
                drawRailDivider(at: buttonX + dividerWidth / 2 - gap, in: frame, ctx: ctx)
                buttonX += dividerWidth
            }
        }
    }

    private func drawRailDivider(at x: CGFloat, in frame: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: x, y: frame.minY + 12))
        ctx.addLine(to: CGPoint(x: x, y: frame.maxY - 12))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawOrigin(for rect: CGRect, in ctx: CGContext) {
        let origin = NSAttributedString(
            string: "↖  \(Int(rect.minX.rounded())) , \(Int((bounds.height - rect.maxY).rounded()))",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                         .foregroundColor: NSColor.white.withAlphaComponent(0.55)]
        )
        let size = origin.size()
        let point = CGPoint(x: min(bounds.maxX - size.width - 8, rect.maxX - size.width),
                            y: rect.maxY + 10)
        origin.draw(at: point)
    }

    private func drawChrome(_ frame: CGRect, radius: CGFloat, in ctx: CGContext) {
        let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.setFillColor(NSColor(calibratedRed: 0.051, green: 0.063, blue: 0.082, alpha: 0.96).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(0.75)
        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawCentered(_ text: String, in frame: CGRect, font: NSFont, color: NSColor) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = string.size()
        string.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }

    private func hitIntent(at point: CGPoint) -> SelectionSurfaceIntent? {
        intentButtonFrames.first { $0.value.contains(point) }?.key
    }

    private func hitMarkupTool(at point: CGPoint) -> SelectionMarkupTool? {
        markupButtonFrames.first { $0.value.contains(point) }?.key
    }

    private func hitAction(at point: CGPoint) -> SelectionSurfaceAction? {
        actionButtonFrames.first { $0.value.contains(point) }?.key
    }

    private func refreshAccessibilityProxies() {
        var elements: [SelectionAccessibilityButton] = []

        for tool in SelectionMarkupTool.allCases {
            guard let frame = markupButtonFrames[tool] else { continue }
            let selected = tool == markupTool ? ", selected" : ""
            elements.append(SelectionAccessibilityButton(
                owner: self,
                identifier: "selection.markup.\(tool.label.lowercased())",
                frame: frame,
                label: "\(tool.label) capture tool\(selected)"
            ) { [weak self] in
                self?.markupTool = tool
                self?.needsDisplay = true
            })
        }

        for intent in availableSurfaceIntents {
            guard let frame = intentButtonFrames[intent] else { continue }
            let state = intent == surfaceIntent ? ", selected" : ""
            elements.append(SelectionAccessibilityButton(
                owner: self,
                identifier: "selection.intent.\(intent.rawValue)",
                frame: frame,
                label: "\(intent.title) capture mode\(state)"
            ) { [weak self] in
                guard let self else { return }
                self.surfaceIntent = intent
                self.onIntentSelected?(intent)
                self.pointerOverChrome = true
                self.needsDisplay = true
            })
        }

        if !aspectButtonFrame.isEmpty {
            elements.append(SelectionAccessibilityButton(
                owner: self,
                identifier: "selection.aspect-lock",
                frame: aspectButtonFrame,
                label: "Aspect ratio lock: \(aspectLock.displayName)"
            ) { [weak self] in
                guard let self else { return }
                let options = SelectionAspectLock.allCases
                let index = options.firstIndex(of: self.aspectLock) ?? 0
                self.onAspectLockSelected?(options[(index + 1) % options.count])
            })
        }

        let actionOrder: [SelectionSurfaceAction] = [.copy, .save, .destination, .annotate, .pin, .shareSafe, .grabText, .record, .dismiss]
        for action in actionOrder {
            guard let frame = actionButtonFrames[action] else { continue }
            elements.append(SelectionAccessibilityButton(
                owner: self,
                identifier: "selection.action.\(action)",
                frame: frame,
                label: action == .destination ? "Destination: \(destinations[destinationIndex])" : action.label
            ) { [weak self] in
                guard let self else { return }
                if action == .destination {
                    destinationIndex = (destinationIndex + 1) % destinations.count
                    needsDisplay = true
                }
                onContextAction?(action)
            })
        }

        accessibilityProxies = elements
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
        let scaleBadge = "@\(Int(display.scale.rounded()))×"
        if let badge = aspectLock.badgeLabel {
            return "\(width) × \(height) · \(badge) · \(scaleBadge)"
        }
        return "\(width) × \(height) · \(scaleBadge)"
    }

    private static let labelFont: NSFont = {
        if let menlo = NSFont(name: "Menlo-Bold", size: 11) { return menlo }
        return NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    }()

    private static let emptyImage: CGImage = {
        CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }()

    @discardableResult
    private func drawLabel(_ text: String, near rect: CGRect, in ctx: CGContext) -> CGRect {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont,
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + 10)
        if origin.y + size.height + 6 > bounds.height - 4 {
            origin.y = rect.maxY - size.height - 10
        }
        origin.x = max(4, min(origin.x, bounds.width - size.width - 4))
        
        drawPill(str, at: origin, horizontalPadding: 8, verticalPadding: 3, cornerRadius: 5, in: ctx)
        return CGRect(x: origin.x - 8,
                      y: origin.y - 3,
                      width: size.width + 16,
                      height: size.height + 6)
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

    private final class SelectionAccessibilityButton: NSObject, NSAccessibilityButton {
        weak var owner: SelectionOverlayView?
        private let identifier: String
        private let frameInParent: CGRect
        private let labelText: String
        private let action: () -> Void

        init(owner: SelectionOverlayView,
             identifier: String,
             frame: CGRect,
             label: String,
             action: @escaping () -> Void) {
            self.owner = owner
            self.identifier = identifier
            self.frameInParent = frame
            self.labelText = label
            self.action = action
        }

        func accessibilityFrame() -> NSRect {
            guard let owner, let window = owner.window else { return .zero }
            return window.convertToScreen(owner.convert(frameInParent, to: nil))
        }

        func accessibilityParent() -> Any? { owner }

        func accessibilityLabel() -> String? { labelText }

        func accessibilityPerformPress() -> Bool {
            guard owner != nil else { return false }
            action()
            return true
        }

        var accessibilityIdentifier: String? { identifier }
    }
}
