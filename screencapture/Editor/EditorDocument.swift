import AppKit
import Combine

/// The model behind an editor window: base image + annotations + crop +
/// beautify settings, with a command-pattern undo stack.
@MainActor
final class EditorDocument: ObservableObject {
    let baseImage: CGImage

    @Published var annotations: [Annotation] = []
    @Published var cropRect: CGRect?  // in image pixels, top-left origin
    @Published var beautify = BeautifySettings()
    @Published var selectedAnnotationID: UUID?
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

    /// Fully rendered output (redaction baked, annotations drawn, crop applied,
    /// beautify applied) — the exact WYSIWYG export.
    func renderFinal() -> CGImage? {
        AnnotationRenderer.renderFinal(document: self)
    }
}
