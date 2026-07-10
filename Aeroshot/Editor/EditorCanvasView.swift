import AppKit
import SwiftUI

/// Layer-backed canvas: base image layer, cached redaction rendering,
/// annotation layer, and live tool preview. Drawing happens in image-pixel
/// coordinates mapped to the view with a uniform fit transform.
final class EditorCanvasNSView: NSView, NSTextViewDelegate, NSDraggingSource {

    let document: EditorDocument
    var toolKind: ToolKind = .arrow
    var style = ToolStyle()

    private let redaction: RedactionFilter
    private var inProgress: Annotation?
    private var activeTool: AnnotationTool?
    private enum SelectionDrag {
        case move(original: Annotation, grabOffset: CGPoint)
        case resize(original: Annotation, handleIndex: Int)
    }
    private var selectionDrag: SelectionDrag?
    private var cropDraft: CGRect?
    private var cropDragStart: CGPoint?
    private var cropResize: (original: CGRect, handle: Int)?
    private var exportDragOrigin: NSPoint?
    private var textEditor: NSTextView?
    private var editingAnnotationID: UUID?
    
    private var isSpacePressed = false
    private var panDragStart: CGPoint?
    private var trackingArea: NSTrackingArea?

    init(document: EditorDocument) {
        self.document = document
        self.redaction = RedactionFilter(baseImage: document.baseImage)
        super.init(frame: .zero)
        wantsLayer = true
        if #available(macOS 10.15, *) {
            layer?.backgroundColor = NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                    return NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)
                } else {
                    return NSColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1.0)
                }
            }.cgColor
        } else {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }  // view coords top-left origin, matching image space

    // MARK: - Transform between view space and image pixels

    /// The base bounds-fit frame of the image without zoom/pan applied.
    var baseImageFrame: CGRect {
        let size = document.pixelSize
        guard size.width > 0, size.height > 0, bounds.width > 20, bounds.height > 20 else { return .zero }
        let available = bounds.insetBy(dx: 16, dy: 16)
        let scale = min(available.width / size.width, available.height / size.height, 1.0)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    /// The actual image frame in view coordinates after applying zoom and pan offset.
    var currentImageFrame: CGRect {
        let base = baseImageFrame
        let w = base.width * document.zoomScale
        let h = base.height * document.zoomScale
        let x = (bounds.midX + document.panOffset.x) - w / 2
        let y = (bounds.midY + document.panOffset.y) - h / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    var viewToImageScale: CGFloat {
        let f = currentImageFrame
        guard f.width > 0 else { return 1 }
        return document.pixelSize.width / f.width
    }

    func imagePoint(fromViewPoint p: CGPoint) -> CGPoint {
        let f = currentImageFrame
        let s = viewToImageScale
        return CGPoint(x: (p.x - f.minX) * s, y: (p.y - f.minY) * s)
    }

    func viewPoint(fromImagePoint p: CGPoint) -> CGPoint {
        let f = currentImageFrame
        let s = viewToImageScale
        return CGPoint(x: p.x / s + f.minX, y: p.y / s + f.minY)
    }

    func viewRect(fromImageRect r: CGRect) -> CGRect {
        let a = viewPoint(fromImagePoint: r.origin)
        let s = viewToImageScale
        return CGRect(x: a.x, y: a.y, width: r.width / s, height: r.height / s)
    }

    // MARK: - Zoom and Pan helper functions & gestures

    func zoom(to newScale: CGFloat, aroundMousePoint mouseViewP: CGPoint) {
        let imgP = imagePoint(fromViewPoint: mouseViewP)
        document.zoomScale = newScale
        
        let newViewP = viewPoint(fromImagePoint: imgP)
        document.panOffset.x += mouseViewP.x - newViewP.x
        document.panOffset.y += mouseViewP.y - newViewP.y
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        let mouseViewP = convert(event.locationInWindow, from: nil)
        let factor = 1.0 + event.magnification
        let newScale = max(0.1, min(10.0, document.zoomScale * factor))
        zoom(to: newScale, aroundMousePoint: mouseViewP)
    }

    override func scrollWheel(with event: NSEvent) {
        let mouseViewP = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.option) {
            // Zoom
            let dy = event.scrollingDeltaY
            let factor: CGFloat = dy > 0 ? 1.08 : 0.92
            let newScale = max(0.1, min(10.0, document.zoomScale * factor))
            zoom(to: newScale, aroundMousePoint: mouseViewP)
        } else {
            // Pan
            document.panOffset.x += event.scrollingDeltaX
            document.panOffset.y += event.scrollingDeltaY
            needsDisplay = true
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        commitTextEditingIfNeeded()
        window?.makeFirstResponder(self)
        
        if isSpacePressed || toolKind == .pan {
            panDragStart = event.locationInWindow
            NSCursor.closedHand.set()
            return
        }

        let viewP = convert(event.locationInWindow, from: nil)
        guard currentImageFrame.insetBy(dx: -8, dy: -8).contains(viewP) else { return }
        let imgP = imagePoint(fromViewPoint: viewP)

        switch toolKind {
        case .select:
            if let id = document.selectedAnnotationID,
               let selected = document.annotation(withID: id),
               let handle = AnnotationSelectionController.handleHit(
                   at: imgP, annotation: selected, tolerance: max(1, 8 * viewToImageScale)
               ), selected.handles().count > 1 {
                selectionDrag = .resize(original: selected, handleIndex: handle.index)
                exportDragOrigin = nil
                needsDisplay = true
                return
            }
            if let hit = document.annotations.reversed().first(where: {
                $0.hitTest(imgP, tolerance: max(1, 6 * viewToImageScale))
            }) {
                document.selectedAnnotationID = hit.id
                let anchor = hit.points.first ?? .zero
                selectionDrag = .move(original: hit, grabOffset: CGPoint(x: imgP.x - anchor.x, y: imgP.y - anchor.y))
                exportDragOrigin = nil
            } else {
                document.selectedAnnotationID = nil
                exportDragOrigin = viewP
            }
            needsDisplay = true
        case .crop:
            if let existing = document.pendingCropRect ?? document.cropRect,
               let handle = cropHandle(at: imgP, rect: existing) {
                document.pendingCropRect = existing
                cropResize = (existing, handle)
                needsDisplay = true
                return
            }
            cropDragStart = imgP
            cropDraft = CGRect(origin: imgP, size: .zero)
            needsDisplay = true
        case .text:
            beginTextEditing(atImagePoint: imgP)
        default:
            guard let tool = ToolFactory.tool(for: toolKind) else { return }
            activeTool = tool
            inProgress = tool.begin(at: imgP, style: style, document: document)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let start = panDragStart {
            let current = event.locationInWindow
            let dx = current.x - start.x
            let dy = -(current.y - start.y)
            document.panOffset.x += dx
            document.panOffset.y += dy
            panDragStart = current
            needsDisplay = true
            return
        }

        if let origin = exportDragOrigin {
            let viewP = convert(event.locationInWindow, from: nil)
            let distance = hypot(viewP.x - origin.x, viewP.y - origin.y)
            if distance > 6 {
                exportDragOrigin = nil
                beginExportDrag(with: event)
            }
            return
        }

        let viewP = convert(event.locationInWindow, from: nil)
        let imgP = imagePoint(fromViewPoint: viewP)

        if var annotation = inProgress, let tool = activeTool {
            tool.update(&annotation, to: imgP)
            inProgress = annotation
            needsDisplay = true
        } else if case let .move(original, offset)? = selectionDrag {
            let delta = CGPoint(x: imgP.x - offset.x - (original.points.first?.x ?? 0),
                                y: imgP.y - offset.y - (original.points.first?.y ?? 0))
            let moved = AnnotationSelectionController.moved(original, by: delta, within: document.pixelSize)
            // Live-preview the move directly (undo command is pushed on mouseUp).
            if let idx = document.annotations.firstIndex(where: { $0.id == original.id }) {
                document.annotations[idx] = moved
            }
            needsDisplay = true
        } else if case let .resize(original, handleIndex)? = selectionDrag {
            let resized = AnnotationSelectionController.resized(
                original, handleIndex: handleIndex, to: imgP, within: document.pixelSize
            )
            if let idx = document.annotations.firstIndex(where: { $0.id == original.id }) {
                document.annotations[idx] = resized
            }
            needsDisplay = true
        } else if let cropResize {
            document.pendingCropRect = constrainedCrop(rectByMovingCorner(cropResize.original, handle: cropResize.handle, to: imgP))
            needsDisplay = true
        } else if let start = cropDragStart {
            cropDraft = constrainedCrop(CGRect(x: min(start.x, imgP.x), y: min(start.y, imgP.y),
                               width: abs(imgP.x - start.x), height: abs(imgP.y - start.y)))
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        exportDragOrigin = nil
        
        if panDragStart != nil {
            panDragStart = nil
            resetCursor()
            return
        }

        if let annotation = inProgress, let tool = activeTool {
            if tool.shouldCommit(annotation) {
                document.perform(AddAnnotationCommand(annotation: annotation))
            }
            inProgress = nil
            activeTool = nil
            needsDisplay = true
        } else if let selectionDrag {
            let original: Annotation
            switch selectionDrag {
            case let .move(value, _), let .resize(value, _): original = value
            }
            if let current = document.annotation(withID: original.id), current != original {
                // Restore pre-drag state, then apply through the undo stack.
                if let idx = document.annotations.firstIndex(where: { $0.id == original.id }) {
                    document.annotations[idx] = original
                }
                document.perform(ModifyAnnotationCommand(before: original, after: current))
            }
            self.selectionDrag = nil
        } else if cropResize != nil {
            cropResize = nil
            needsDisplay = true
        } else if let draft = cropDraft, cropDragStart != nil {
            if draft.width > 8, draft.height > 8 {
                let clamped = draft.intersection(CGRect(origin: .zero, size: document.pixelSize))
                document.pendingCropRect = clamped
            }
            cropDraft = nil
            cropDragStart = nil
            needsDisplay = true
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { // Spacebar
            if !isSpacePressed {
                isSpacePressed = true
                resetCursor()
            }
            return
        }

        switch event.keyCode {
        case 123, 124, 125, 126: // arrows
            let amount: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta: CGPoint = switch event.keyCode {
            case 123: CGPoint(x: -amount, y: 0)
            case 124: CGPoint(x: amount, y: 0)
            case 125: CGPoint(x: 0, y: amount)
            default: CGPoint(x: 0, y: -amount)
            }
            if document.nudgeSelected(by: delta) { needsDisplay = true }
        case 51, 117: // delete / forward delete
            deleteSelectedAnnotation()
        case 53: // esc
            cancelSelectionDrag()
            document.selectedAnnotationID = nil
            cropDraft = nil
            cropResize = nil
            document.cancelPendingCrop()
            needsDisplay = true
        case 36, 76: // return / enter
            if toolKind == .crop { document.applyPendingCrop(); needsDisplay = true }
        default:
            if event.modifierFlags.contains(.command), handleZOrderKey(event) { return }
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { // Spacebar
            isSpacePressed = false
            resetCursor()
            return
        }
        super.keyUp(with: event)
    }

    func deleteSelectedAnnotation() {
        guard let id = document.selectedAnnotationID,
              let idx = document.annotations.firstIndex(where: { $0.id == id }) else { return }
        let annotation = document.annotations[idx]
        document.selectedAnnotationID = nil
        document.perform(RemoveAnnotationCommand(annotation: annotation, index: idx))
        needsDisplay = true
    }

    private func cancelSelectionDrag() {
        guard let selectionDrag else { return }
        let original: Annotation
        switch selectionDrag {
        case let .move(value, _), let .resize(value, _): original = value
        }
        if let index = document.annotations.firstIndex(where: { $0.id == original.id }) {
            document.annotations[index] = original
        }
        self.selectionDrag = nil
    }

    private func handleZOrderKey(_ event: NSEvent) -> Bool {
        // ⌘] / ⌘[ move one layer; Shift moves to the edge.
        guard event.charactersIgnoringModifiers == "]" || event.charactersIgnoringModifiers == "[" else { return false }
        let forward = event.charactersIgnoringModifiers == "]"
        let edge = event.modifierFlags.contains(.shift)
        let order: AnnotationZOrder = forward ? (edge ? .front : .forward) : (edge ? .back : .backward)
        if document.reorderSelected(order) { needsDisplay = true }
        return true
    }

    // MARK: - Middle-click pan

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { // Middle click
            panDragStart = event.locationInWindow
            NSCursor.closedHand.set()
        } else {
            super.otherMouseDown(with: event)
        }
    }

    override func otherMouseDragged(with event: NSEvent) {
        if event.buttonNumber == 2, let start = panDragStart {
            let current = event.locationInWindow
            let dx = current.x - start.x
            let dy = -(current.y - start.y)
            document.panOffset.x += dx
            document.panOffset.y += dy
            panDragStart = current
            needsDisplay = true
        } else {
            super.otherMouseDragged(with: event)
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 && panDragStart != nil {
            panDragStart = nil
            resetCursor()
        } else {
            super.otherMouseUp(with: event)
        }
    }

    // MARK: - Cursor & Tracking

    private func resetCursor() {
        if isSpacePressed || toolKind == .pan {
            NSCursor.openHand.set()
        } else if toolKind == .select {
            NSCursor.arrow.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func updateTrackingAreas() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseMoved, .cursorUpdate]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        resetCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        resetCursor()
    }

    // MARK: - Text editing (NSTextView field editor)

    private func beginTextEditing(atImagePoint imgP: CGPoint) {
        let annotation = Annotation(kind: .text, points: [imgP], color: style.color, fontSize: style.fontSize)
        editingAnnotationID = annotation.id
        // Track the pending annotation without committing until text exists.
        inProgress = annotation

        let viewP = viewPoint(fromImagePoint: imgP)
        let fontSizeInView = style.fontSize / viewToImageScale
        let editor = NSTextView(frame: CGRect(x: viewP.x, y: viewP.y, width: 240, height: fontSizeInView * 1.6))
        editor.font = NSFont.systemFont(ofSize: fontSizeInView, weight: .semibold)
        editor.textColor = style.color
        editor.backgroundColor = NSColor.black.withAlphaComponent(0.15)
        editor.delegate = self
        editor.isRichText = false
        addSubview(editor)
        window?.makeFirstResponder(editor)
        textEditor = editor
    }

    func commitTextEditingIfNeeded() {
        guard let editor = textEditor else { return }
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if var annotation = inProgress, annotation.kind == .text, !text.isEmpty {
            annotation.text = text
            document.perform(AddAnnotationCommand(annotation: annotation))
        }
        editor.removeFromSuperview()
        textEditor = nil
        inProgress = nil
        editingAnnotationID = nil
        needsDisplay = true
    }

    func textDidEndEditing(_ notification: Notification) {
        commitTextEditingIfNeeded()
    }

    // MARK: - Drag-out export (Select tool, drag empty canvas)

    private func beginExportDrag(with event: NSEvent) {
        guard let cgImage = document.renderFinal() else { return }
        let frame = currentImageFrame
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: frame.width, height: frame.height))
        let item = NSPasteboardItem()
        if let data = ImageExporter.data(for: cgImage, format: .png) {
            item.setData(data, forType: .png)
        }
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(frame, contents: nsImage)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        // 0. Draw Dot Grid Background
        ctx.saveGState()
        let gridColor = NSColor.textColor.withAlphaComponent(0.045).cgColor
        ctx.setFillColor(gridColor)
        
        let dotSpacing: CGFloat = 16.0
        let dotSize: CGFloat = 1.2
        
        let offsetX = document.panOffset.x.remainder(dividingBy: dotSpacing)
        let offsetY = document.panOffset.y.remainder(dividingBy: dotSpacing)
        
        let startX = bounds.minX - dotSpacing
        let endX = bounds.maxX + dotSpacing
        let startY = bounds.minY - dotSpacing
        let endY = bounds.maxY + dotSpacing
        
        for x in stride(from: startX, to: endX, by: dotSpacing) {
            for y in stride(from: startY, to: endY, by: dotSpacing) {
                let px = x + offsetX
                let py = y + offsetY
                ctx.fillEllipse(in: CGRect(x: px - dotSize/2, y: py - dotSize/2, width: dotSize, height: dotSize))
            }
        }
        ctx.restoreGState()

        let frame = currentImageFrame
        guard !frame.isEmpty else { return }

        if document.showRuler {
            drawRulers(around: frame, in: ctx)
        }

        // 1. Base image with a beautiful soft drop shadow.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 16, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.translateBy(x: frame.minX, y: frame.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(document.baseImage, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        ctx.restoreGState()

        // 2. Redactions (blur/pixelate draw filtered image; solid fills opaque black).
        let redactions = document.annotations.filter(\.kind.isRedaction)
            + ((inProgress?.kind.isRedaction == true) ? [inProgress!] : [])
        for annotation in redactions {
            let rect = annotation.boundingRect.insetBy(dx: annotation.lineWidth, dy: annotation.lineWidth)
            guard rect.width > 1, rect.height > 1 else { continue }
            let viewRect = self.viewRect(fromImageRect: rect)
            ctx.saveGState()
            switch annotation.kind {
            case .redactSolid:
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fill(viewRect)
            case .redactBlur, .redactPixelate:
                let filtered = annotation.kind == .redactBlur ? redaction.blurredImage() : redaction.pixelatedImage()
                guard let filtered else {
                    ctx.restoreGState()
                    continue
                }
                ctx.clip(to: viewRect)
                ctx.translateBy(x: frame.minX, y: frame.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(filtered, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
            default:
                break
            }
            ctx.restoreGState()
        }

        // 3. Annotations + live preview: draw in image space via scale transform.
        //    View is flipped (top-left origin), which matches image space directly.
        ctx.saveGState()
        ctx.translateBy(x: frame.minX, y: frame.minY)
        let s = 1 / viewToImageScale
        ctx.scaleBy(x: s, y: s)
        for annotation in document.annotations where !annotation.kind.isRedaction {
            guard annotation.id != editingAnnotationID else { continue }
            AnnotationRenderer.draw(annotation, in: ctx)
        }
        if let inProgress, !inProgress.kind.isRedaction,
           editingAnnotationID == nil {
            AnnotationRenderer.draw(inProgress, in: ctx)
        }
        ctx.restoreGState()

        // 4. Selection handles.
        if let id = document.selectedAnnotationID, let selected = document.annotation(withID: id) {
            let r = viewRect(fromImageRect: selected.boundingRect)
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(r.insetBy(dx: -3, dy: -3))
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.setFillColor(NSColor.controlAccentColor.cgColor)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            for handle in selected.handles() {
                let center = viewPoint(fromImagePoint: handle)
                let handleRect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
                ctx.fillEllipse(in: handleRect)
                ctx.strokeEllipse(in: handleRect)
            }
        }

        // 5. Crop overlay.
        let cropToShow = cropDraft ?? document.pendingCropRect ?? (toolKind == .crop ? document.cropRect : nil)
        if let crop = cropToShow, !crop.isEmpty {
            let r = viewRect(fromImageRect: crop)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            // Dim everything outside the crop.
            ctx.saveGState()
            ctx.addRect(frame)
            ctx.addRect(r)
            ctx.clip(using: .evenOdd)
            ctx.fill(frame)
            ctx.restoreGState()
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(r)
            if toolKind == .crop {
                ctx.setFillColor(NSColor.controlAccentColor.cgColor)
                for point in cropCornerPoints(crop) {
                    let center = viewPoint(fromImagePoint: point)
                    ctx.fillEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                }
            }
        } else if let crop = document.cropRect, !crop.isEmpty {
            // Passive indication that a crop exists.
            let r = viewRect(fromImageRect: crop)
            ctx.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.stroke(r)
            ctx.setLineDash(phase: 0, lengths: [])
        }
    }

    private func constrainedCrop(_ rect: CGRect) -> CGRect {
        guard let ratio = document.cropAspectRatio, ratio > 0, rect.width > 0, rect.height > 0 else { return rect }
        var result = rect
        if rect.width / rect.height > ratio { result.size.width = rect.height * ratio }
        else { result.size.height = rect.width / ratio }
        return result.intersection(CGRect(origin: .zero, size: document.pixelSize))
    }

    private func cropCornerPoints(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    private func cropHandle(at point: CGPoint, rect: CGRect) -> Int? {
        cropCornerPoints(rect).enumerated().first { _, corner in hypot(corner.x - point.x, corner.y - point.y) <= 10 * viewToImageScale }.map(\.offset)
    }

    private func rectByMovingCorner(_ rect: CGRect, handle: Int, to point: CGPoint) -> CGRect {
        let opposite = cropCornerPoints(rect)[(handle + 2) % 4]
        return CGRect(x: min(opposite.x, point.x), y: min(opposite.y, point.y),
                      width: abs(point.x - opposite.x), height: abs(point.y - opposite.y))
    }

    private func drawRulers(around frame: NSRect, in ctx: CGContext) {
        let tickSpacing = max(20, 40 / document.zoomScale)
        let rulerThickness: CGFloat = 18

        ctx.saveGState()
        ctx.setFillColor(NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor)
        ctx.fill(CGRect(x: frame.minX, y: frame.maxY, width: frame.width, height: rulerThickness))
        ctx.fill(CGRect(x: frame.minX - rulerThickness, y: frame.minY, width: rulerThickness, height: frame.height))

        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.stroke(CGRect(x: frame.minX, y: frame.maxY, width: frame.width, height: rulerThickness))
        ctx.stroke(CGRect(x: frame.minX - rulerThickness, y: frame.minY, width: rulerThickness, height: frame.height))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        var x = frame.minX
        var imageX: CGFloat = 0
        while x <= frame.maxX {
            ctx.move(to: CGPoint(x: x, y: frame.maxY))
            ctx.addLine(to: CGPoint(x: x, y: frame.maxY + 6))
            let label = NSAttributedString(string: "\(Int(imageX))", attributes: attrs)
            label.draw(at: NSPoint(x: x + 2, y: frame.maxY + 2))
            x += tickSpacing
            imageX += tickSpacing / document.zoomScale
        }

        var y = frame.maxY
        var imageY: CGFloat = 0
        while y >= frame.minY {
            ctx.move(to: CGPoint(x: frame.minX - 6, y: y))
            ctx.addLine(to: CGPoint(x: frame.minX, y: y))
            let label = NSAttributedString(string: "\(Int(imageY))", attributes: attrs)
            label.draw(at: NSPoint(x: frame.minX - rulerThickness + 2, y: y - 10))
            y -= tickSpacing
            imageY += tickSpacing / document.zoomScale
        }
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - SwiftUI wrapper

struct EditorCanvasView: NSViewRepresentable {
    @ObservedObject var document: EditorDocument
    var toolKind: ToolKind
    var style: ToolStyle

    func makeNSView(context: Context) -> EditorCanvasNSView {
        EditorCanvasNSView(document: document)
    }

    func updateNSView(_ nsView: EditorCanvasNSView, context: Context) {
        nsView.toolKind = toolKind
        nsView.style = style
        nsView.needsDisplay = true
    }
}
