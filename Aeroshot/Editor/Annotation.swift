import AppKit

enum AnnotationKind: String, Codable {
    case arrow, rectangle, ellipse, line, freehand, highlighter, text, redactBlur, redactPixelate, redactSolid, step

    var isRedaction: Bool {
        switch self {
        case .redactBlur, .redactPixelate, .redactSolid: return true
        default: return false
        }
    }
}

/// A single annotation on the canvas. Geometry is stored in image-pixel
/// coordinates with a top-left origin so rendering is resolution-exact.
struct Annotation: Identifiable, Equatable {
    let id: UUID
    var kind: AnnotationKind
    /// For shapes/arrows/lines: start & end. For text/step: origin at points[0].
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var text: String
    var fontSize: CGFloat
    var stepNumber: Int
    var filled: Bool

    init(id: UUID = UUID(),
         kind: AnnotationKind,
         points: [CGPoint] = [],
         color: NSColor = .systemRed,
         lineWidth: CGFloat = 4,
         text: String = "",
         fontSize: CGFloat = 24,
         stepNumber: Int = 1,
         filled: Bool = false) {
        self.id = id
        self.kind = kind
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.fontSize = fontSize
        self.stepNumber = stepNumber
        self.filled = filled
    }

    var boundingRect: CGRect {
        switch kind {
        case .text:
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)]
            let size = (text.isEmpty ? " " : text).size(withAttributes: attrs)
            let origin = points.first ?? .zero
            return CGRect(origin: origin, size: CGSize(width: size.width + 8, height: size.height + 4))
        case .step:
            let r = fontSize * 1.2
            let c = points.first ?? .zero
            return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        case .freehand, .highlighter:
            guard !points.isEmpty else { return .zero }
            var minX = CGFloat.greatestFiniteMagnitude, minY = minX
            var maxX = -CGFloat.greatestFiniteMagnitude, maxY = maxX
            for p in points {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: -lineWidth, dy: -lineWidth)
        default:
            guard points.count >= 2 else { return .zero }
            let a = points[0], b = points[1]
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                          width: abs(b.x - a.x), height: abs(b.y - a.y))
                .insetBy(dx: -lineWidth, dy: -lineWidth)
        }
    }

    func hitTest(_ point: CGPoint) -> Bool {
        boundingRect.insetBy(dx: -6, dy: -6).contains(point)
    }
}
