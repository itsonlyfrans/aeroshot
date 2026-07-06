import AppKit
import CoreText

/// Shared drawing code used by both the live canvas and export, guaranteeing
/// WYSIWYG. All drawing happens in image-pixel coordinates with a *top-left*
/// origin (the context is pre-flipped by callers using `flip(context:height:)`).
enum AnnotationRenderer {

    /// Flip a bottom-left-origin CGContext so subsequent drawing uses
    /// top-left-origin coordinates.
    static func flip(context: CGContext, height: CGFloat) {
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
    }

    // MARK: - Full composition

    /// Render base + redactions + annotations into a new image (no crop/beautify).
    static func renderAnnotated(document: EditorDocument, redaction: RedactionFilter? = nil) -> CGImage? {
        let base = document.baseImage
        let w = base.width, h = base.height
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Base image (CGContext draws bottom-left; image fills the full rect so no flip needed).
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))

        let filter = redaction ?? RedactionFilter(baseImage: base)
        // Bake redactions: blur/pixelate draw filtered image; solid fills opaque black.
        let redactions = document.annotations.filter(\.kind.isRedaction)
        for annotation in redactions {
            let rect = annotation.boundingRect.insetBy(dx: annotation.lineWidth, dy: annotation.lineWidth)
            guard !rect.isEmpty else { continue }
            let flippedRect = CGRect(x: rect.origin.x, y: CGFloat(h) - rect.maxY, width: rect.width, height: rect.height)
            ctx.saveGState()
            switch annotation.kind {
            case .redactSolid:
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fill(flippedRect)
            case .redactBlur, .redactPixelate:
                ctx.clip(to: flippedRect)
                let filtered = annotation.kind == .redactBlur ? filter.blurredImage() : filter.pixelatedImage()
                guard let filtered else {
                    ctx.restoreGState()
                    continue
                }
                ctx.draw(filtered, in: CGRect(x: 0, y: 0, width: w, height: h))
            default:
                break
            }
            ctx.restoreGState()
        }

        // Annotations draw in top-left coordinates: flip.
        ctx.saveGState()
        flip(context: ctx, height: CGFloat(h))
        for annotation in document.annotations where !annotation.kind.isRedaction {
            draw(annotation, in: ctx)
        }
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// Full pipeline: annotate → crop → beautify.
    static func renderFinal(document: EditorDocument) -> CGImage? {
        guard var image = renderAnnotated(document: document) else { return nil }
        if let crop = document.cropRect, !crop.isEmpty {
            if let cropped = image.cropping(to: crop.integral) {
                image = cropped
            }
        }
        if document.beautify.enabled {
            if let beautified = BeautifyRenderer.render(image: image, settings: document.beautify) {
                image = beautified
            }
        }
        return image
    }

    // MARK: - Single annotation (top-left-origin flipped context)

    static func draw(_ annotation: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let color = annotation.color.cgColor
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(annotation.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch annotation.kind {
        case .arrow:
            guard annotation.points.count >= 2 else { return }
            drawArrow(from: annotation.points[0], to: annotation.points[1],
                      lineWidth: annotation.lineWidth, in: ctx)
        case .line:
            guard annotation.points.count >= 2 else { return }
            ctx.move(to: annotation.points[0])
            ctx.addLine(to: annotation.points[1])
            ctx.strokePath()
        case .rectangle:
            let rect = annotation.boundingRect.insetBy(dx: annotation.lineWidth, dy: annotation.lineWidth)
            let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
            ctx.addPath(path)
            annotation.filled ? ctx.fillPath() : ctx.strokePath()
        case .ellipse:
            let rect = annotation.boundingRect.insetBy(dx: annotation.lineWidth, dy: annotation.lineWidth)
            annotation.filled ? ctx.fillEllipse(in: rect) : ctx.strokeEllipse(in: rect)
        case .freehand:
            strokePolyline(annotation.points, in: ctx)
        case .highlighter:
            ctx.setStrokeColor(annotation.color.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(annotation.lineWidth * 3)
            ctx.setBlendMode(.multiply)
            strokePolyline(annotation.points, in: ctx)
        case .text:
            drawText(annotation, in: ctx)
        case .step:
            drawStep(annotation, in: ctx)
        case .redactBlur, .redactPixelate, .redactSolid:
            break  // baked separately
        }
    }

    private static func strokePolyline(_ points: [CGPoint], in ctx: CGContext) {
        guard points.count > 1 else { return }
        ctx.move(to: points[0])
        for p in points.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat, in ctx: CGContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(lineWidth * 4, 14)
        let headAngle: CGFloat = .pi / 7
        let lineEnd = CGPoint(x: end.x - cos(angle) * headLength * 0.6,
                              y: end.y - sin(angle) * headLength * 0.6)
        ctx.move(to: start)
        ctx.addLine(to: lineEnd)
        ctx.strokePath()

        let p1 = CGPoint(x: end.x - cos(angle - headAngle) * headLength,
                         y: end.y - sin(angle - headAngle) * headLength)
        let p2 = CGPoint(x: end.x - cos(angle + headAngle) * headLength,
                         y: end.y - sin(angle + headAngle) * headLength)
        ctx.move(to: end)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }

    private static func drawText(_ annotation: Annotation, in ctx: CGContext) {
        guard !annotation.text.isEmpty, let origin = annotation.points.first else { return }
        let font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.color,
        ]
        let attributed = NSAttributedString(string: annotation.text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.saveGState()
        // Text draws in an unflipped space: flip locally around the text box.
        ctx.translateBy(x: origin.x, y: origin.y + bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = CGPoint(x: 0, y: -bounds.minY - bounds.height + font.ascender)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static func drawStep(_ annotation: Annotation, in ctx: CGContext) {
        guard let center = annotation.points.first else { return }
        let radius = annotation.fontSize * 1.2
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.setFillColor(annotation.color.cgColor)
        ctx.fillEllipse(in: circle)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(max(2, annotation.fontSize / 10))
        ctx.strokeEllipse(in: circle.insetBy(dx: 1, dy: 1))

        let text = "\(annotation.stepNumber)"
        let font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.saveGState()
        ctx.translateBy(x: center.x - bounds.width / 2, y: center.y + bounds.height / 2)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = CGPoint(x: 0, y: -bounds.minY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
