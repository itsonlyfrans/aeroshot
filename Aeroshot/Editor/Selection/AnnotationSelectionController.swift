import AppKit

struct AnnotationSelection: Equatable {
    var orderedIDs: [UUID] = []
    var primaryID: UUID?

    static let empty = AnnotationSelection()

    init(orderedIDs: [UUID] = [], primaryID: UUID? = nil) {
        var seen = Set<UUID>()
        self.orderedIDs = orderedIDs.filter { seen.insert($0).inserted }
        self.primaryID = primaryID.flatMap { self.orderedIDs.contains($0) ? $0 : nil } ?? self.orderedIDs.last
    }

    var isEmpty: Bool { orderedIDs.isEmpty }
    var count: Int { orderedIDs.count }
    func contains(_ id: UUID) -> Bool { orderedIDs.contains(id) }

    func normalized(for annotations: [Annotation]) -> AnnotationSelection {
        let selected = Set(orderedIDs)
        let ids = annotations.map(\.id).filter(selected.contains)
        return AnnotationSelection(orderedIDs: ids, primaryID: primaryID)
    }
}

enum AnnotationZOrder: Equatable {
    case forward
    case backward
    case front
    case back
}

struct AnnotationHandleHit: Equatable {
    let annotationID: UUID
    let index: Int
}

/// Pure image-space selection transforms. The canvas owns gesture state while
/// this type keeps hit testing and geometry rules deterministic and testable.
enum AnnotationSelectionController {
    static let minimumDimension: CGFloat = 1

    static func marqueeSelection(in rect: CGRect, annotations: [Annotation]) -> AnnotationSelection {
        guard !rect.isNull, !rect.isEmpty else { return .empty }
        let ids = annotations.filter { AnnotationGeometry.bounds(for: $0).intersects(rect) }.map(\.id)
        return AnnotationSelection(orderedIDs: ids, primaryID: ids.last)
    }

    static func bounds(of annotations: [Annotation]) -> CGRect? {
        annotations.map { AnnotationGeometry.bounds(for: $0) }.reduce(nil) { result, rect in
            result.map { $0.union(rect) } ?? rect
        }
    }

    static func commonTranslation(for annotations: [Annotation], requested delta: CGPoint, within size: CGSize) -> CGPoint {
        guard delta != .zero else { return .zero }
        guard let bounds = bounds(of: annotations) else { return .zero }
        return CGPoint(
            x: directionalDelta(delta.x, minimum: -bounds.minX, maximum: size.width - bounds.maxX),
            y: directionalDelta(delta.y, minimum: -bounds.minY, maximum: size.height - bounds.maxY)
        )
    }

    private static func directionalDelta(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        if value > 0 { return maximum > 0 ? min(value, maximum) : 0 }
        if value < 0 { return minimum < 0 ? max(value, minimum) : 0 }
        return 0
    }

    static func moved(_ annotations: [Annotation], by delta: CGPoint, within size: CGSize) -> [Annotation] {
        let translation = commonTranslation(for: annotations, requested: delta, within: size)
        guard translation != .zero else { return annotations }
        return annotations.map { annotation in
            var result = annotation
            result.points = result.points.map { CGPoint(x: $0.x + translation.x, y: $0.y + translation.y) }
            return result
        }
    }

    static func handleHit(
        at point: CGPoint,
        annotation: Annotation,
        tolerance: CGFloat
    ) -> AnnotationHandleHit? {
        let tolerance = max(0, tolerance)
        return annotation.handles().enumerated().reversed().first { _, handle in
            hypot(point.x - handle.x, point.y - handle.y) <= tolerance
        }.map { AnnotationHandleHit(annotationID: annotation.id, index: $0.offset) }
    }

    static func moved(_ annotation: Annotation, by delta: CGPoint, within size: CGSize) -> Annotation {
        guard !annotation.points.isEmpty else { return annotation }
        guard delta != .zero else { return annotation }
        let bounds = annotation.boundingRect
        let dx = clampedDelta(delta.x, minimum: -bounds.minX, maximum: size.width - bounds.maxX)
        let dy = clampedDelta(delta.y, minimum: -bounds.minY, maximum: size.height - bounds.maxY)
        guard dx != 0 || dy != 0 else { return annotation }
        var result = annotation
        result.points = annotation.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return result
    }

    static func resized(
        _ annotation: Annotation,
        handleIndex: Int,
        to point: CGPoint,
        within size: CGSize
    ) -> Annotation {
        guard annotation.points.count >= 2 else { return annotation }
        let point = CGPoint(x: min(max(0, point.x), size.width), y: min(max(0, point.y), size.height))
        var result = annotation
        switch annotation.kind {
        case .line, .arrow, .freehand, .highlighter:
            guard handleIndex == 0 || handleIndex == 1 else { return annotation }
            let pointIndex = handleIndex == 0 ? 0 : result.points.count - 1
            let oppositeIndex = handleIndex == 0 ? result.points.count - 1 : 0
            guard hypot(point.x - result.points[oppositeIndex].x, point.y - result.points[oppositeIndex].y) >= minimumDimension else {
                return annotation
            }
            result.points[pointIndex] = point
        case .rectangle, .ellipse, .redactBlur, .redactPixelate, .redactSolid:
            guard (0..<4).contains(handleIndex) else { return annotation }
            let rect = normalizedEndpointRect(annotation.points)
            let opposite = [
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
            ][handleIndex]
            let x = separated(point.x, from: opposite.x, preferredSign: handleIndex == 0 || handleIndex == 3 ? -1 : 1, limit: size.width)
            let y = separated(point.y, from: opposite.y, preferredSign: handleIndex == 0 || handleIndex == 1 ? -1 : 1, limit: size.height)
            result.points = [opposite, CGPoint(x: x, y: y)]
        case .text, .step:
            return annotation
        }
        return result
    }

    private static func normalizedEndpointRect(_ points: [CGPoint]) -> CGRect {
        CGRect(x: min(points[0].x, points[1].x), y: min(points[0].y, points[1].y),
               width: abs(points[1].x - points[0].x), height: abs(points[1].y - points[0].y))
    }

    private static func separated(_ value: CGFloat, from opposite: CGFloat, preferredSign: CGFloat, limit: CGFloat) -> CGFloat {
        if abs(value - opposite) >= minimumDimension { return value }
        let preferred = opposite + preferredSign * minimumDimension
        if preferred >= 0, preferred <= limit { return preferred }
        return min(max(0, opposite - preferredSign * minimumDimension), limit)
    }

    private static func clampedDelta(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else { return 0 }
        return min(max(value, minimum), maximum)
    }
}
