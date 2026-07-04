import AppKit
import SwiftUI

/// Layer-backed canvas: base image layer, cached redaction rendering,
/// annotation layer, and live tool preview. Drawing happens in image-pixel
/// coordinates mapped to the view with a uniform fit transform.
final class EditorCanvasNSView: NSView, NSTextViewDelegate {

    let document: EditorDocument
    var toolKind: ToolKind = .arrow
    var style = ToolStyle()

    private let redaction: RedactionFilter
    private var inProgress: Annotation?
    private var activeTool: AnnotationTool?
    private var draggingAnnotation: (original: Annotation, grabOffset: CGPoint)?
    private var cropDraft: CGRect?
    private var cropDragStart: CGPoint?
    private var textEditor: NSTextView?
    private var editingAnnotationID: UUID?

    init(document: EditorDocument) {
        self.document = document
        self.redaction = RedactionFilter(baseImage: document.baseImage)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }  // view coords top-left origin, matching image space

    // MARK: - Transform between view space and image pixels

    /// Rect (in view coordinates) where the image is drawn, aspect-fit with margin.
    var imageFrameInView: CGRect {
        let size = document.pixelSize
        guard size.width > 0, size.height > 0, bounds.width > 20, bounds.height > 20 else { return .zero }
        let available = bounds.insetBy(dx: 16, dy: 16)
        let scale = min(available.width / size.width, available.height / size.height, 1.0)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    var viewToImageScale: CGFloat {
        let f = imageFrameInView
        guard f.width > 0 else { return 1 }
        return document.pixelSize.width / f.width
    }

    func imagePoint(fromViewPoint p: CGPoint) -> CGPoint {
        let f = imageFrameInView
        let s = viewToImageScale
        return CGPoint(x: (p.x - f.minX) * s, y: (p.y - f.minY) * s)
    }

    func viewPoint(fromImagePoint p: CGPoint) -> CGPoint {
        let f = imageFrameInView
        let s = viewToImageScale
        return CGPoint(x: p.x / s + f.minX, y: p.y / s + f.minY)
    }

    func viewRect(fromImageRect r: CGRect) -> CGRect {
        let a = viewPoint(fromImagePoint: r.origin)
        let s = viewToImageScale
        return CGRect(x: a.x, y: a.y, width: r.width / s, height: r.height / s)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        commitTextEditingIfNeeded()
        window?.makeFirstResponder(self)
        let viewP = convert(event.locationInWindow, from: nil)
        guard imageFrameInView.insetBy(dx: -8, dy: -8).contains(viewP) else { return }
        let imgP = imagePoint(fromViewPoint: viewP)

        switch toolKind {
        case .select:
            if let hit = document.annotations.reversed().first(where: { $0.hitTest(imgP) }) {
                document.selectedAnnotationID = hit.id
                let anchor = hit.points.first ?? .zero
                draggingAnnotation = (hit, CGPoint(x: imgP.x - anchor.x, y: imgP.y - anchor.y))
            } else {
                document.selectedAnnotationID = nil
            }
            needsDisplay = true
        case .crop:
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
        let viewP = convert(event.locationInWindow, from: nil)
        let imgP = imagePoint(fromViewPoint: viewP)

        if var annotation = inProgress, let tool = activeTool {
            tool.update(&annotation, to: imgP)
            inProgress = annotation
            needsDisplay = true
        } else if let (original, offset) = draggingAnnotation {
            var moved = original
            let delta = CGPoint(x: imgP.x - offset.x - (original.points.first?.x ?? 0),
                                y: imgP.y - offset.y - (original.points.first?.y ?? 0))
            moved.points = original.points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
            // Live-preview the move directly (undo command is pushed on mouseUp).
            if let idx = document.annotations.firstIndex(where: { $0.id == original.id }) {
                document.annotations[idx] = moved
            }
            needsDisplay = true
        } else if let start = cropDragStart {
            cropDraft = CGRect(x: min(start.x, imgP.x), y: min(start.y, imgP.y),
                               width: abs(imgP.x - start.x), height: abs(imgP.y - start.y))
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let annotation = inProgress, let tool = activeTool {
            if tool.shouldCommit(annotation) {
                document.perform(AddAnnotationCommand(annotation: annotation))
            }
            inProgress = nil
            activeTool = nil
            needsDisplay = true
        } else if let (original, _) = draggingAnnotation {
            if let current = document.annotation(withID: original.id), current != original {
                // Restore pre-drag state, then apply through the undo stack.
                if let idx = document.annotations.firstIndex(where: { $0.id == original.id }) {
                    document.annotations[idx] = original
                }
                document.perform(ModifyAnnotationCommand(before: original, after: current))
            }
            draggingAnnotation = nil
        } else if let draft = cropDraft, cropDragStart != nil {
            if draft.width > 8, draft.height > 8 {
                let clamped = draft.intersection(CGRect(origin: .zero, size: document.pixelSize))
                document.perform(SetCropCommand(before: document.cropRect, after: clamped.integral))
            }
            cropDraft = nil
            cropDragStart = nil
            needsDisplay = true
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // delete / forward delete
            deleteSelectedAnnotation()
        case 53: // esc
            document.selectedAnnotationID = nil
            cropDraft = nil
            needsDisplay = true
        default:
            super.keyDown(with: event)
        }
    }

    func deleteSelectedAnnotation() {
        guard let id = document.selectedAnnotationID,
              let idx = document.annotations.firstIndex(where: { $0.id == id }) else { return }
        let annotation = document.annotations[idx]
        document.selectedAnnotationID = nil
        document.perform(RemoveAnnotationCommand(annotation: annotation, index: idx))
        needsDisplay = true
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

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let frame = imageFrameInView
        guard !frame.isEmpty else { return }

        // 1. Base image. View is flipped; CGContext.draw expects unflipped, so flip locally.
        ctx.saveGState()
        ctx.translateBy(x: frame.minX, y: frame.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(document.baseImage, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        ctx.restoreGState()

        // 2. Redactions (draw cached filtered image clipped to each redact rect).
        let redactions = document.annotations.filter { $0.kind == .redactBlur || $0.kind == .redactPixelate }
            + ((inProgress?.kind == .redactBlur || inProgress?.kind == .redactPixelate) ? [inProgress!] : [])
        for annotation in redactions {
            let rect = annotation.boundingRect.insetBy(dx: annotation.lineWidth, dy: annotation.lineWidth)
            guard rect.width > 1, rect.height > 1 else { continue }
            let filtered = annotation.kind == .redactBlur ? redaction.blurredImage() : redaction.pixelatedImage()
            guard let filtered else { continue }
            let viewRect = self.viewRect(fromImageRect: rect)
            ctx.saveGState()
            ctx.clip(to: viewRect)
            ctx.translateBy(x: frame.minX, y: frame.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(filtered, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
            ctx.restoreGState()
        }

        // 3. Annotations + live preview: draw in image space via scale transform.
        //    View is flipped (top-left origin), which matches image space directly.
        ctx.saveGState()
        ctx.translateBy(x: frame.minX, y: frame.minY)
        let s = 1 / viewToImageScale
        ctx.scaleBy(x: s, y: s)
        for annotation in document.annotations where annotation.kind != .redactBlur && annotation.kind != .redactPixelate {
            guard annotation.id != editingAnnotationID else { continue }
            AnnotationRenderer.draw(annotation, in: ctx)
        }
        if let inProgress, inProgress.kind != .redactBlur, inProgress.kind != .redactPixelate,
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
        }

        // 5. Crop overlay.
        let cropToShow = cropDraft ?? (toolKind == .crop ? document.cropRect : nil)
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
