import AppKit

/// Deterministic image-space geometry shared by interaction, preview, and export.
/// Callers convert a screen-space hit slop to image pixels before passing it as
/// `tolerance`, keeping selection behavior independent of canvas zoom.
enum AnnotationGeometry {
    struct ArrowGeometry {
        struct Head {
            var path: CGPath
            var style: AnnotationArrowheadStyle
        }

        var shaft: CGPath
        var startHead: Head?
        var endHead: Head?
    }

    static func path(for annotation: Annotation) -> CGPath? {
        switch annotation.kind {
        case .arrow:
            return arrowGeometry(for: annotation)?.shaft
        case .line, .freehand, .highlighter:
            return polylinePath(annotation.points)
        case .rectangle:
            guard let rect = endpointRect(annotation.points) else { return nil }
            return CGPath(
                roundedRect: rect,
                cornerWidth: max(0, annotation.appearance.cornerRadius),
                cornerHeight: max(0, annotation.appearance.cornerRadius),
                transform: nil
            )
        case .redactBlur, .redactPixelate, .redactSolid:
            guard let rect = endpointRect(annotation.points) else { return nil }
            let path = CGMutablePath()
            path.addRect(rect)
            return path
        case .ellipse:
            guard let rect = endpointRect(annotation.points) else { return nil }
            return CGPath(ellipseIn: rect, transform: nil)
        case .text:
            let path = CGMutablePath()
            path.addRect(textBounds(for: annotation))
            return path
        case .step:
            let path = CGMutablePath()
            path.addEllipse(in: stepBounds(for: annotation))
            return path
        }
    }

    static func bounds(for annotation: Annotation) -> CGRect {
        switch annotation.kind {
        case .text:
            return textBounds(for: annotation)
        case .step:
            return stepBounds(for: annotation)
        case .arrow:
            guard let geometry = arrowGeometry(for: annotation) else { return .zero }
            var result = strokedBounds(geometry.shaft, width: annotation.lineWidth)
            for head in [geometry.startHead, geometry.endHead].compactMap({ $0 }) {
                let headBounds = head.style == .filled
                    ? head.path.boundingBoxOfPath
                    : strokedBounds(head.path, width: annotation.lineWidth)
                result = result.union(headBounds)
            }
            return result
        case .freehand, .highlighter:
            guard let path = polylinePath(annotation.points) else { return .zero }
            let width = annotation.kind == .highlighter ? annotation.lineWidth * 3 : annotation.lineWidth
            return strokedBounds(path, width: width)
        default:
            guard let rect = endpointRect(annotation.points) else { return .zero }
            return rect.insetBy(dx: -annotation.lineWidth, dy: -annotation.lineWidth)
        }
    }

    static func handles(for annotation: Annotation) -> [CGPoint] {
        switch annotation.kind {
        case .line, .arrow, .freehand, .highlighter:
            guard let first = annotation.points.first, let last = annotation.points.last else { return [] }
            return first == last ? [first] : [first, last]
        case .text, .step:
            return annotation.points.first.map { [$0] } ?? []
        case .rectangle, .ellipse, .redactBlur, .redactPixelate, .redactSolid:
            guard let rect = endpointRect(annotation.points) else { return [] }
            return [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY),
            ]
        }
    }

    static func hitTest(_ point: CGPoint, annotation: Annotation, tolerance: CGFloat) -> Bool {
        guard !annotation.points.isEmpty else { return false }
        let tolerance = max(0, tolerance)
        let coarseBounds = bounds(for: annotation).insetBy(dx: -tolerance, dy: -tolerance)
        guard point.x >= coarseBounds.minX, point.x <= coarseBounds.maxX,
              point.y >= coarseBounds.minY, point.y <= coarseBounds.maxY else {
            return false
        }

        switch annotation.kind {
        case .text:
            return textBounds(for: annotation).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .step:
            return ellipseContains(point, rect: stepBounds(for: annotation), tolerance: tolerance)
        case .redactBlur, .redactPixelate, .redactSolid:
            return endpointRect(annotation.points)?.insetBy(dx: -tolerance, dy: -tolerance).contains(point) ?? false
        case .rectangle, .ellipse:
            guard let path = path(for: annotation) else { return false }
            if annotation.filled, path.contains(point) { return true }
            return strokedContains(point, path: path, width: annotation.lineWidth + tolerance * 2)
        case .line, .freehand, .highlighter:
            guard let path = path(for: annotation) else { return false }
            let width = annotation.kind == .highlighter ? annotation.lineWidth * 3 : annotation.lineWidth
            return strokedContains(point, path: path, width: width + tolerance * 2)
        case .arrow:
            guard let geometry = arrowGeometry(for: annotation) else { return false }
            if strokedContains(point, path: geometry.shaft, width: annotation.lineWidth + tolerance * 2) {
                return true
            }
            return [geometry.startHead, geometry.endHead].compactMap({ $0 }).contains { head in
                head.style == .filled
                    ? strokedContains(point, path: head.path, width: max(annotation.lineWidth, tolerance * 2)) || head.path.contains(point)
                    : strokedContains(point, path: head.path, width: annotation.lineWidth + tolerance * 2)
            }
        }
    }

    static func arrowGeometry(for annotation: Annotation) -> ArrowGeometry? {
        guard annotation.kind == .arrow, annotation.points.count >= 2 else { return nil }
        let start = annotation.points[0]
        let end = annotation.points[1]
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let distance = hypot(delta.x, delta.y)
        guard distance > .ulpOfOne else { return nil }

        let style = annotation.appearance.arrow
        let unit = CGPoint(x: delta.x / distance, y: delta.y / distance)
        let normal = CGPoint(x: -unit.y, y: unit.x)
        let midpoint = CGPoint(
            x: (start.x + end.x) / 2 + normal.x * style.curve,
            y: (start.y + end.y) / 2 + normal.y * style.curve
        )
        let startTangent = normalized(CGPoint(x: midpoint.x - start.x, y: midpoint.y - start.y), fallback: unit)
        let endTangent = normalized(CGPoint(x: end.x - midpoint.x, y: end.y - midpoint.y), fallback: unit)
        let headLength = max(0, style.headLength ?? max(annotation.lineWidth * 4, 14))
        let headWidth = max(0, style.headWidth ?? (2 * sin(.pi / 7) * headLength))
        let inset = max(0, style.inset ?? headLength * 0.6)
        let shaftStart = style.startStyle == .none
            ? start
            : CGPoint(x: start.x + startTangent.x * inset, y: start.y + startTangent.y * inset)
        let shaftEnd = style.endStyle == .none
            ? end
            : CGPoint(x: end.x - endTangent.x * inset, y: end.y - endTangent.y * inset)

        let shaft = CGMutablePath()
        shaft.move(to: shaftStart)
        if style.curve == 0 {
            shaft.addLine(to: shaftEnd)
        } else {
            let c1 = CGPoint(x: shaftStart.x + (midpoint.x - shaftStart.x) * 2 / 3,
                             y: shaftStart.y + (midpoint.y - shaftStart.y) * 2 / 3)
            let c2 = CGPoint(x: shaftEnd.x + (midpoint.x - shaftEnd.x) * 2 / 3,
                             y: shaftEnd.y + (midpoint.y - shaftEnd.y) * 2 / 3)
            shaft.addCurve(to: shaftEnd, control1: c1, control2: c2)
        }

        return ArrowGeometry(
            shaft: shaft,
            startHead: arrowHead(at: start, direction: CGPoint(x: -startTangent.x, y: -startTangent.y), length: headLength, width: headWidth, style: style.startStyle),
            endHead: arrowHead(at: end, direction: endTangent, length: headLength, width: headWidth, style: style.endStyle)
        )
    }

    static func textBounds(for annotation: Annotation) -> CGRect {
        guard annotation.points.first != nil else { return .zero }
        let font = font(for: annotation)
        if annotation.appearance.typography == AnnotationTypography() {
            let size = (annotation.text.isEmpty ? " " : annotation.text).size(withAttributes: [.font: font])
            return CGRect(
                origin: annotation.points.first ?? .zero,
                size: CGSize(width: size.width + 8, height: size.height + 4)
            )
        }
        let lines = (annotation.text.isEmpty ? " " : annotation.text).components(separatedBy: "\n")
        let naturalLineHeight = font.ascender - font.descender + font.leading
        let lineHeight = naturalLineHeight * max(0, annotation.appearance.typography.lineHeight)
        let width = lines.map { ($0.isEmpty ? " " : $0).size(withAttributes: [.font: font]).width }.max() ?? 0
        let padding = annotation.appearance.typography.padding
        return CGRect(
            origin: annotation.points.first ?? .zero,
            size: CGSize(
                width: width + padding.leading + padding.trailing,
                height: lineHeight * CGFloat(lines.count) + padding.top + padding.bottom
            )
        )
    }

    static func font(for annotation: Annotation) -> NSFont {
        let typography = annotation.appearance.typography
        if let name = typography.fontName, let font = NSFont(name: name, size: annotation.fontSize) {
            return font
        }
        return NSFont.systemFont(ofSize: annotation.fontSize, weight: typography.weight)
    }

    private static func endpointRect(_ points: [CGPoint]) -> CGRect? {
        guard points.count >= 2 else { return nil }
        return CGRect(
            x: min(points[0].x, points[1].x),
            y: min(points[0].y, points[1].y),
            width: abs(points[1].x - points[0].x),
            height: abs(points[1].y - points[0].y)
        )
    }

    private static func polylinePath(_ points: [CGPoint]) -> CGPath? {
        guard !points.isEmpty else { return nil }
        let path = CGMutablePath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private static func stepBounds(for annotation: Annotation) -> CGRect {
        guard annotation.points.first != nil else { return .zero }
        let radius = annotation.fontSize * 1.2
        let center = annotation.points.first ?? .zero
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    private static func arrowHead(
        at tip: CGPoint,
        direction: CGPoint,
        length: CGFloat,
        width: CGFloat,
        style: AnnotationArrowheadStyle
    ) -> ArrowGeometry.Head? {
        guard style != .none else { return nil }
        let halfWidth = min(width / 2, length)
        // `length` is the sloping edge length, matching the historical arrowhead.
        let baseDistance = sqrt(max(0, length * length - halfWidth * halfWidth))
        let base = CGPoint(x: tip.x - direction.x * baseDistance, y: tip.y - direction.y * baseDistance)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let first = CGPoint(x: base.x + normal.x * halfWidth, y: base.y + normal.y * halfWidth)
        let second = CGPoint(x: base.x - normal.x * halfWidth, y: base.y - normal.y * halfWidth)
        let path = CGMutablePath()
        if style == .filled {
            path.move(to: tip)
            path.addLine(to: first)
            path.addLine(to: second)
            path.closeSubpath()
        } else {
            path.move(to: first)
            path.addLine(to: tip)
            path.addLine(to: second)
        }
        return ArrowGeometry.Head(path: path, style: style)
    }

    private static func normalized(_ point: CGPoint, fallback: CGPoint) -> CGPoint {
        let length = hypot(point.x, point.y)
        guard length > .ulpOfOne else { return fallback }
        return CGPoint(x: point.x / length, y: point.y / length)
    }

    private static func strokedBounds(_ path: CGPath, width: CGFloat) -> CGRect {
        path.copy(
            strokingWithWidth: max(0, width),
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10
        ).boundingBoxOfPath
    }

    private static func strokedContains(_ point: CGPoint, path: CGPath, width: CGFloat) -> Bool {
        path.copy(
            strokingWithWidth: max(0, width),
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10
        ).contains(point)
    }

    private static func ellipseContains(_ point: CGPoint, rect: CGRect, tolerance: CGFloat) -> Bool {
        let expanded = rect.insetBy(dx: -tolerance, dy: -tolerance)
        guard expanded.width > 0, expanded.height > 0 else { return false }
        let dx = (point.x - expanded.midX) / (expanded.width / 2)
        let dy = (point.y - expanded.midY) / (expanded.height / 2)
        return dx * dx + dy * dy <= 1
    }
}
