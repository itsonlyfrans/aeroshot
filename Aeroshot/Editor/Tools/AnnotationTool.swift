import AppKit

/// Style parameters shared across tools.
struct ToolStyle {
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var fontSize: CGFloat = 24
    var filled: Bool = false
    var appearance: AnnotationAppearance = AnnotationAppearance()
}

/// A drawing tool. Points arrive in image-pixel coordinates (top-left origin).
/// Tools build an in-progress Annotation; when finished, the canvas commits it
/// to the document via an AddAnnotationCommand.
@MainActor
protocol AnnotationTool {
    var kind: ToolKind { get }
    /// Begin a gesture; return the initial in-progress annotation (or nil if the
    /// tool doesn't produce one, e.g. Select).
    func begin(at point: CGPoint, style: ToolStyle, document: EditorDocument) -> Annotation?
    /// Update the in-progress annotation as the pointer moves.
    func update(_ annotation: inout Annotation, to point: CGPoint)
    /// Final validation before commit. Return false to discard (e.g. zero-size shape).
    func shouldCommit(_ annotation: Annotation) -> Bool
}

enum ToolKind: String, CaseIterable, Identifiable {
    case select, pan, arrow, line, rectangle, ellipse, freehand, highlighter, text, redactBlur, redactPixelate, redactSolid, step, crop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .select: return "Select"
        case .pan: return "Pan"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .freehand: return "Draw"
        case .highlighter: return "Highlight"
        case .text: return "Text"
        case .redactBlur: return "Blur"
        case .redactPixelate: return "Pixelate"
        case .redactSolid: return "Redact"
        case .step: return "Step"
        case .crop: return "Crop"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pan: return "hand.raised"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .freehand: return "pencil.and.scribble"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .redactBlur: return "drop.halffull"
        case .redactPixelate: return "squareshape.split.3x3"
        case .redactSolid: return "rectangle.fill"
        case .step: return "1.circle"
        case .crop: return "crop"
        }
    }
}

// MARK: - Implementations

struct TwoPointTool: AnnotationTool {
    let kind: ToolKind
    private let annotationKind: AnnotationKind

    init(kind: ToolKind) {
        self.kind = kind
        switch kind {
        case .arrow: annotationKind = .arrow
        case .line: annotationKind = .line
        case .rectangle: annotationKind = .rectangle
        case .ellipse: annotationKind = .ellipse
        case .redactBlur: annotationKind = .redactBlur
        case .redactPixelate: annotationKind = .redactPixelate
        case .redactSolid: annotationKind = .redactSolid
        default: annotationKind = .rectangle
        }
    }

    func begin(at point: CGPoint, style: ToolStyle, document: EditorDocument) -> Annotation? {
        Annotation(kind: annotationKind, points: [point, point],
                   color: style.color, lineWidth: style.lineWidth, filled: style.filled,
                   appearance: style.appearance)
    }

    func update(_ annotation: inout Annotation, to point: CGPoint) {
        annotation.points[1] = point
    }

    func shouldCommit(_ annotation: Annotation) -> Bool {
        guard annotation.points.count >= 2 else { return false }
        let a = annotation.points[0], b = annotation.points[1]
        return hypot(b.x - a.x, b.y - a.y) > 3
    }
}

struct PolylineTool: AnnotationTool {
    let kind: ToolKind

    func begin(at point: CGPoint, style: ToolStyle, document: EditorDocument) -> Annotation? {
        Annotation(kind: kind == .highlighter ? .highlighter : .freehand,
                   points: [point], color: style.color, lineWidth: style.lineWidth,
                   appearance: style.appearance)
    }

    func update(_ annotation: inout Annotation, to point: CGPoint) {
        annotation.points.append(point)
    }

    func shouldCommit(_ annotation: Annotation) -> Bool {
        annotation.points.count > 1
    }
}

struct StepTool: AnnotationTool {
    let kind: ToolKind = .step

    func begin(at point: CGPoint, style: ToolStyle, document: EditorDocument) -> Annotation? {
        Annotation(kind: .step, points: [point], color: style.color,
                   fontSize: style.fontSize, stepNumber: document.nextStepNumber,
                   appearance: style.appearance)
    }

    func update(_ annotation: inout Annotation, to point: CGPoint) {
        annotation.points[0] = point
    }

    func shouldCommit(_ annotation: Annotation) -> Bool { true }
}

struct TextTool: AnnotationTool {
    let kind: ToolKind = .text

    func begin(at point: CGPoint, style: ToolStyle, document: EditorDocument) -> Annotation? {
        Annotation(kind: .text, points: [point], color: style.color, fontSize: style.fontSize,
                   appearance: style.appearance)
    }

    func update(_ annotation: inout Annotation, to point: CGPoint) {
        annotation.points[0] = point
    }

    // Text commits only after editing produces content; canvas handles that.
    func shouldCommit(_ annotation: Annotation) -> Bool { !annotation.text.isEmpty }
}

enum ToolFactory {
    @MainActor
    static func tool(for kind: ToolKind) -> AnnotationTool? {
        switch kind {
        case .select, .crop, .pan:
            return nil  // handled directly by the canvas
        case .arrow, .line, .rectangle, .ellipse, .redactBlur, .redactPixelate, .redactSolid:
            return TwoPointTool(kind: kind)
        case .freehand, .highlighter:
            return PolylineTool(kind: kind)
        case .text:
            return TextTool()
        case .step:
            return StepTool()
        }
    }
}
