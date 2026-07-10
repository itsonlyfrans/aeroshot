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

enum AnnotationLineCap: String, Equatable {
    case butt, round, square

    var cgLineCap: CGLineCap {
        switch self {
        case .butt: .butt
        case .round: .round
        case .square: .square
        }
    }
}

struct AnnotationShadow: Equatable {
    var color: NSColor
    var opacity: CGFloat
    var radius: CGFloat
    var offset: CGSize

    init(color: NSColor = .black, opacity: CGFloat = 0, radius: CGFloat = 0, offset: CGSize = .zero) {
        self.color = color
        self.opacity = opacity
        self.radius = radius
        self.offset = offset
    }
}

struct AnnotationStrokeAppearance: Equatable {
    var opacity: CGFloat
    var dash: [CGFloat]
    var dashPhase: CGFloat
    var lineCap: AnnotationLineCap
    var shadow: AnnotationShadow

    init(
        opacity: CGFloat = 1,
        dash: [CGFloat] = [],
        dashPhase: CGFloat = 0,
        lineCap: AnnotationLineCap = .round,
        shadow: AnnotationShadow = AnnotationShadow()
    ) {
        self.opacity = opacity
        self.dash = dash
        self.dashPhase = dashPhase
        self.lineCap = lineCap
        self.shadow = shadow
    }
}

struct AnnotationFillAppearance: Equatable {
    var opacity: CGFloat

    init(opacity: CGFloat = 1) {
        self.opacity = opacity
    }
}

enum AnnotationArrowheadStyle: String, Equatable {
    case none, open, filled
}

struct AnnotationArrowAppearance: Equatable {
    var startStyle: AnnotationArrowheadStyle
    var endStyle: AnnotationArrowheadStyle
    /// Nil preserves the historical `max(lineWidth * 4, 14)` behavior.
    var headLength: CGFloat?
    /// Nil preserves the historical `.pi / 7` half-angle behavior.
    var headWidth: CGFloat?
    /// Nil preserves the historical `headLength * 0.6` shaft inset.
    var inset: CGFloat?
    /// Signed perpendicular displacement, in image pixels, at the curve midpoint.
    var curve: CGFloat

    init(
        startStyle: AnnotationArrowheadStyle = .none,
        endStyle: AnnotationArrowheadStyle = .filled,
        headLength: CGFloat? = nil,
        headWidth: CGFloat? = nil,
        inset: CGFloat? = nil,
        curve: CGFloat = 0
    ) {
        self.startStyle = startStyle
        self.endStyle = endStyle
        self.headLength = headLength
        self.headWidth = headWidth
        self.inset = inset
        self.curve = curve
    }
}

enum AnnotationTextAlignment: String, Equatable {
    case leading, center, trailing
}

struct AnnotationInsets: Equatable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    /// The asymmetric default preserves the previous text bounding box exactly.
    init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 4, trailing: CGFloat = 8) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

struct AnnotationTypography: Equatable {
    var fontName: String?
    var weight: NSFont.Weight
    var alignment: AnnotationTextAlignment
    var backgroundColor: NSColor?
    var backgroundOpacity: CGFloat
    var padding: AnnotationInsets
    /// A multiplier of the font's natural line height. One preserves legacy output.
    var lineHeight: CGFloat

    init(
        fontName: String? = nil,
        weight: NSFont.Weight = .semibold,
        alignment: AnnotationTextAlignment = .leading,
        backgroundColor: NSColor? = nil,
        backgroundOpacity: CGFloat = 1,
        padding: AnnotationInsets = AnnotationInsets(),
        lineHeight: CGFloat = 1
    ) {
        self.fontName = fontName
        self.weight = weight
        self.alignment = alignment
        self.backgroundColor = backgroundColor
        self.backgroundOpacity = backgroundOpacity
        self.padding = padding
        self.lineHeight = lineHeight
    }
}

struct AnnotationAppearance: Equatable {
    var stroke: AnnotationStrokeAppearance
    var fill: AnnotationFillAppearance
    var cornerRadius: CGFloat
    var arrow: AnnotationArrowAppearance
    var typography: AnnotationTypography

    init(
        stroke: AnnotationStrokeAppearance = AnnotationStrokeAppearance(),
        fill: AnnotationFillAppearance = AnnotationFillAppearance(),
        cornerRadius: CGFloat = 2,
        arrow: AnnotationArrowAppearance = AnnotationArrowAppearance(),
        typography: AnnotationTypography = AnnotationTypography()
    ) {
        self.stroke = stroke
        self.fill = fill
        self.cornerRadius = cornerRadius
        self.arrow = arrow
        self.typography = typography
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
    var appearance: AnnotationAppearance

    /// The original initializer is intentionally preserved, including every
    /// label and default. `appearance` is additive and defaults to legacy output.
    init(id: UUID = UUID(),
         kind: AnnotationKind,
         points: [CGPoint] = [],
         color: NSColor = .systemRed,
         lineWidth: CGFloat = 4,
         text: String = "",
         fontSize: CGFloat = 24,
         stepNumber: Int = 1,
         filled: Bool = false,
         appearance: AnnotationAppearance = AnnotationAppearance()) {
        self.id = id
        self.kind = kind
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.fontSize = fontSize
        self.stepNumber = stepNumber
        self.filled = filled
        self.appearance = appearance
    }

    var boundingRect: CGRect {
        AnnotationGeometry.bounds(for: self)
    }

    func handles() -> [CGPoint] {
        AnnotationGeometry.handles(for: self)
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat = 6) -> Bool {
        AnnotationGeometry.hitTest(point, annotation: self, tolerance: tolerance)
    }
}
