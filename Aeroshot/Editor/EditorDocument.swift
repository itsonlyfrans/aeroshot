import AppKit
import Combine

/// The model behind an editor window: base image + annotations + crop +
/// beautify settings, with a command-pattern undo stack.
@MainActor
final class EditorDocument: ObservableObject {
    let baseImage: CGImage

    @Published var annotations: [Annotation] = []
    @Published var cropRect: CGRect?  // in image pixels, top-left origin
    @Published var pendingCropRect: CGRect?
    @Published var cropAspectRatio: CGFloat?
    @Published var straightenDegrees: Double = 0
    @Published var beautify = BeautifySettings()
    @Published var selectedAnnotationID: UUID?
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGPoint = .zero
    @Published var showRuler = false
    @Published private(set) var undoTick: Int = 0

    let undoStack = UndoStack()

    var nextStepNumber: Int {
        (annotations.filter { $0.kind == .step }.map(\.stepNumber).max() ?? 0) + 1
    }

    init(image: CGImage) {
        self.baseImage = image
    }

    var pixelSize: CGSize {
        CGSize(width: baseImage.width, height: baseImage.height)
    }

    // MARK: - Mutations (all via commands)

    func perform(_ command: DocumentCommand) {
        undoStack.push(command, apply: self)
        undoTick += 1
    }

    func undo() {
        undoStack.undo(on: self)
        undoTick += 1
    }

    func redo() {
        undoStack.redo(on: self)
        undoTick += 1
    }

    func annotation(withID id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    @discardableResult
    func transformAnnotation(id: UUID, to transformed: Annotation) -> Bool {
        guard let original = annotation(withID: id), original != transformed, transformed.id == id else { return false }
        perform(ModifyAnnotationCommand(before: original, after: transformed))
        return true
    }

    @discardableResult
    func nudgeSelected(by delta: CGPoint) -> Bool {
        guard let id = selectedAnnotationID, let annotation = annotation(withID: id) else { return false }
        return transformAnnotation(id: id, to: AnnotationSelectionController.moved(annotation, by: delta, within: pixelSize))
    }

    @discardableResult
    func reorderSelected(_ order: AnnotationZOrder) -> Bool {
        guard let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return false }
        let canMove = switch order {
        case .forward, .front: index < annotations.count - 1
        case .backward, .back: index > 0
        }
        guard canMove else { return false }
        let destination = switch order {
        case .forward: index + 1
        case .backward: index - 1
        case .front: annotations.count - 1
        case .back: 0
        }
        perform(ReorderAnnotationCommand(annotationID: id, fromIndex: index, toIndex: destination))
        return true
    }

    /// Fully rendered output (redaction baked, annotations drawn, crop applied,
    /// beautify applied) — the exact WYSIWYG export.
    func renderFinal() -> CGImage? {
        AnnotationRenderer.renderFinal(document: self)
    }

    func applyPendingCrop() {
        guard let pendingCropRect else { return }
        perform(SetCropCommand(before: cropRect, after: pendingCropRect.integral))
        self.pendingCropRect = nil
    }

    func cancelPendingCrop() { pendingCropRect = nil }

    func applyTemplate(_ template: AnnotationTemplate) {
        let annotations = template.makeAnnotations(for: pixelSize)
        guard !annotations.isEmpty else { return }
        perform(ApplyTemplateCommand(annotations: annotations))
    }
}
