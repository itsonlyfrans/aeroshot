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
                ctx.setFillColor(NSColor.black.withAlphaComponent(clamped(annotation.appearance.fill.opacity)).cgColor)
                ctx.fill(flippedRect)
            case .redactBlur, .redactPixelate:
                ctx.clip(to: flippedRect)
                ctx.setAlpha(clamped(annotation.appearance.fill.opacity))
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
        applyAppearance(of: annotation, in: ctx)
        ctx.setLineJoin(.round)

        switch annotation.kind {
        case .arrow:
            drawArrow(annotation, in: ctx)
        case .line:
            guard let path = AnnotationGeometry.path(for: annotation) else { return }
            ctx.addPath(path)
            ctx.strokePath()
        case .rectangle:
            guard let path = AnnotationGeometry.path(for: annotation) else { return }
            ctx.addPath(path)
            annotation.filled ? ctx.fillPath() : ctx.strokePath()
        case .ellipse:
            guard let path = AnnotationGeometry.path(for: annotation) else { return }
            ctx.addPath(path)
            annotation.filled ? ctx.fillPath() : ctx.strokePath()
        case .freehand:
            strokePath(for: annotation, in: ctx)
        case .highlighter:
            ctx.setStrokeColor(color(annotation.color, multiplyingAlphaBy: annotation.appearance.stroke.opacity * 0.4).cgColor)
            ctx.setLineWidth(annotation.lineWidth * 3)
            ctx.setBlendMode(.multiply)
            strokePath(for: annotation, in: ctx)
        case .text:
            drawText(annotation, in: ctx)
        case .step:
            drawStep(annotation, in: ctx)
        case .redactBlur, .redactPixelate, .redactSolid:
            break  // baked separately
        }
    }

    private static func strokePath(for annotation: Annotation, in ctx: CGContext) {
        guard annotation.points.count > 1, let path = AnnotationGeometry.path(for: annotation) else { return }
        ctx.addPath(path)
        ctx.strokePath()
    }

    private static func drawArrow(_ annotation: Annotation, in ctx: CGContext) {
        guard let geometry = AnnotationGeometry.arrowGeometry(for: annotation) else { return }
        ctx.addPath(geometry.shaft)
        ctx.strokePath()
        for head in [geometry.startHead, geometry.endHead].compactMap({ $0 }) {
            ctx.addPath(head.path)
            head.style == .filled ? ctx.fillPath() : ctx.strokePath()
        }
    }

    private static func drawText(_ annotation: Annotation, in ctx: CGContext) {
        guard !annotation.text.isEmpty, let origin = annotation.points.first else { return }
        let font = AnnotationGeometry.font(for: annotation)
        let typography = annotation.appearance.typography
        let bounds = AnnotationGeometry.textBounds(for: annotation)
        if let background = typography.backgroundColor {
            ctx.setFillColor(color(background, multiplyingAlphaBy: typography.backgroundOpacity).cgColor)
            let radius = max(0, annotation.appearance.cornerRadius)
            ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
        }

        if typography == AnnotationTypography() {
            drawLegacyText(
                annotation.text,
                origin: origin,
                font: font,
                color: color(annotation.color, multiplyingAlphaBy: annotation.appearance.stroke.opacity),
                in: ctx
            )
            return
        }

        let padding = typography.padding
        let lines = annotation.text.components(separatedBy: "\n")
        let naturalLineHeight = font.ascender - font.descender + font.leading
        let lineHeight = naturalLineHeight * max(0, typography.lineHeight)
        for (index, text) in lines.enumerated() {
            let attributed = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color(annotation.color, multiplyingAlphaBy: annotation.appearance.stroke.opacity),
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            let lineBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            let availableWidth = max(0, bounds.width - padding.leading - padding.trailing)
            let alignmentOffset: CGFloat = switch typography.alignment {
            case .leading: 0
            case .center: (availableWidth - lineBounds.width) / 2
            case .trailing: availableWidth - lineBounds.width
            }
            let lineOrigin = CGPoint(
                x: origin.x + padding.leading + alignmentOffset,
                y: origin.y + padding.top + CGFloat(index) * lineHeight
            )
            drawCoreTextLine(line, origin: lineOrigin, bounds: lineBounds, font: font, in: ctx)
        }
    }

    private static func drawLegacyText(
        _ text: String,
        origin: CGPoint,
        font: NSFont,
        color: NSColor,
        in ctx: CGContext
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        drawCoreTextLine(line, origin: origin, bounds: bounds, font: font, in: ctx)
    }

    private static func drawCoreTextLine(
        _ line: CTLine,
        origin: CGPoint,
        bounds: CGRect,
        font: NSFont,
        in ctx: CGContext
    ) {
        ctx.saveGState()
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
        ctx.setFillColor(color(annotation.color, multiplyingAlphaBy: annotation.appearance.fill.opacity).cgColor)
        ctx.fillEllipse(in: circle)
        let foreground = color(NSColor.white, multiplyingAlphaBy: annotation.appearance.stroke.opacity)
        ctx.setStrokeColor(foreground.cgColor)
        ctx.setLineWidth(max(2, annotation.fontSize / 10))
        ctx.strokeEllipse(in: circle.insetBy(dx: 1, dy: 1))

        let text = "\(annotation.stepNumber)"
        let font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
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

    static func applyAppearance(of annotation: Annotation, in ctx: CGContext) {
        let stroke = annotation.appearance.stroke
        ctx.setStrokeColor(color(annotation.color, multiplyingAlphaBy: stroke.opacity).cgColor)
        ctx.setFillColor(color(annotation.color, multiplyingAlphaBy: annotation.appearance.fill.opacity).cgColor)
        ctx.setLineWidth(max(0, annotation.lineWidth))
        ctx.setLineCap(stroke.lineCap.cgLineCap)
        ctx.setLineDash(phase: stroke.dashPhase, lengths: stroke.dash.map { max(0, $0) })
        let shadow = stroke.shadow
        if shadow.opacity > 0, shadow.radius > 0 {
            ctx.setShadow(
                offset: shadow.offset,
                blur: shadow.radius,
                color: color(shadow.color, multiplyingAlphaBy: shadow.opacity).cgColor
            )
        }
    }

    static func color(_ color: NSColor, multiplyingAlphaBy opacity: CGFloat) -> NSColor {
        color.withAlphaComponent(color.alphaComponent * clamped(opacity))
    }

    static func clamped(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }
}
