import AppKit
import Combine

/// The model behind an editor window: base image + annotations + crop +
/// beautify settings, with a command-pattern undo stack.
@MainActor
final class EditorDocument: ObservableObject {
    let baseImage: CGImage

    @Published var annotations: [Annotation] = [] {
        didSet { selection = selection.normalized(for: annotations) }
    }
    @Published var cropRect: CGRect?  // in image pixels, top-left origin
    @Published var pendingCropRect: CGRect?
    @Published var cropAspectRatio: CGFloat?
    @Published var straightenDegrees: Double = 0
    @Published var beautify = BeautifySettings()
    @Published var selection = AnnotationSelection.empty {
        didSet {
            let normalized = selection.normalized(for: annotations)
            if normalized != selection { selection = normalized }
        }
    }
    @Published var selectedToolKind: ToolKind = .arrow
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

    var selectedAnnotations: [Annotation] {
        let ids = Set(selection.orderedIDs)
        return annotations.filter { ids.contains($0.id) }
    }

    var primarySelectedAnnotation: Annotation? {
        selection.primaryID.flatMap(annotation(withID:))
    }

    func selectOnly(_ id: UUID?) {
        selection = id.flatMap { annotation(withID: $0) == nil ? nil : AnnotationSelection(orderedIDs: [$0], primaryID: $0) } ?? .empty
    }

    func toggleSelection(_ id: UUID) {
        guard annotation(withID: id) != nil else { return }
        var selected = Set(selection.orderedIDs)
        if selected.remove(id) != nil {
            let ids = annotations.map(\.id).filter(selected.contains)
            selection = AnnotationSelection(orderedIDs: ids, primaryID: selection.primaryID == id ? ids.last : selection.primaryID)
        } else {
            selected.insert(id)
            let ids = annotations.map(\.id).filter(selected.contains)
            selection = AnnotationSelection(orderedIDs: ids, primaryID: id)
        }
    }

    func makePrimary(_ id: UUID) {
        guard selection.contains(id) else { return }
        selection.primaryID = id
    }

    func selectAll() {
        let ids = annotations.map(\.id)
        selection = AnnotationSelection(orderedIDs: ids, primaryID: ids.last)
    }

    @discardableResult
    func duplicateSelected(offset: CGPoint = CGPoint(x: 12, y: 12)) -> [Annotation] {
        let originals = selectedAnnotations
        guard !originals.isEmpty else { return [] }
        var moved = AnnotationSelectionController.moved(originals, by: offset, within: pixelSize)
        if moved == originals {
            moved = AnnotationSelectionController.moved(originals, by: CGPoint(x: -offset.x, y: -offset.y), within: pixelSize)
        }
        let copies = moved.map { annotation in
            Annotation(kind: annotation.kind, points: annotation.points, color: annotation.color,
                       lineWidth: annotation.lineWidth, text: annotation.text, fontSize: annotation.fontSize,
                       stepNumber: annotation.stepNumber, filled: annotation.filled, appearance: annotation.appearance)
        }
        let before = annotations
        var after = annotations
        after.append(contentsOf: copies)
        let copyByOriginalID = Dictionary(uniqueKeysWithValues: zip(originals.map(\.id), copies.map(\.id)))
        let next = AnnotationSelection(
            orderedIDs: copies.map(\.id),
            primaryID: selection.primaryID.flatMap { copyByOriginalID[$0] } ?? copies.last?.id
        )
        perform(AnnotationBatchCommand(before: before, after: after, selectionBefore: selection, selectionAfter: next, name: "Duplicate annotations"))
        return copies
    }

    @discardableResult
    func insertCopy(of annotation: Annotation, offset: CGPoint = CGPoint(x: 12, y: 12)) -> Annotation {
        var copy = Annotation(
            kind: annotation.kind,
            points: annotation.points,
            color: annotation.color,
            lineWidth: annotation.lineWidth,
            text: annotation.text,
            fontSize: annotation.fontSize,
            stepNumber: annotation.stepNumber,
            filled: annotation.filled,
            appearance: annotation.appearance
        )
        let forward = AnnotationSelectionController.moved(copy, by: offset, within: pixelSize)
        let backward = AnnotationSelectionController.moved(copy, by: CGPoint(x: -offset.x, y: -offset.y), within: pixelSize)
        if forward != copy {
            copy = forward
        } else if backward != copy {
            copy = backward
        }
        let bounds = copy.boundingRect
        let margin = min(12, pixelSize.width / 2, pixelSize.height / 2)
        let dx: CGFloat = bounds.maxX <= 0 ? margin - bounds.maxX
            : (bounds.minX >= pixelSize.width ? pixelSize.width - margin - bounds.minX : 0)
        let dy: CGFloat = bounds.maxY <= 0 ? margin - bounds.maxY
            : (bounds.minY >= pixelSize.height ? pixelSize.height - margin - bounds.minY : 0)
        if dx != 0 || dy != 0 {
            copy.points = copy.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        }
        perform(AddAnnotationCommand(annotation: copy, selectionBefore: selection, selectsAnnotation: true))
        return copy
    }

    @discardableResult
    func editTextAnnotation(id: UUID, text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var annotation = annotation(withID: id), annotation.kind == .text else { return false }
        annotation.text = text
        return transformAnnotation(id: id, to: annotation)
    }

    @discardableResult
    func transformAnnotation(id: UUID, to transformed: Annotation) -> Bool {
        guard let original = annotation(withID: id), original != transformed, transformed.id == id else { return false }
        perform(ModifyAnnotationCommand(before: original, after: transformed))
        return true
    }

    @discardableResult
    func nudgeSelected(by delta: CGPoint) -> Bool {
        let originals = selectedAnnotations
        let moved = AnnotationSelectionController.moved(originals, by: delta, within: pixelSize)
        guard moved != originals else { return false }
        return replaceSelected(with: moved, name: "Move annotations")
    }

    @discardableResult
    func replaceSelected(with replacements: [Annotation], name: String = "Edit annotations") -> Bool {
        let map = Dictionary(uniqueKeysWithValues: replacements.map { ($0.id, $0) })
        let after = annotations.map { map[$0.id] ?? $0 }
        guard after != annotations else { return false }
        perform(AnnotationBatchCommand(before: annotations, after: after, selectionBefore: selection, selectionAfter: selection, name: name))
        return true
    }

    @discardableResult
    func deleteSelected() -> Bool {
        let ids = Set(selection.orderedIDs)
        guard !ids.isEmpty else { return false }
        perform(AnnotationBatchCommand(before: annotations, after: annotations.filter { !ids.contains($0.id) }, selectionBefore: selection, selectionAfter: .empty, name: "Delete annotations"))
        return true
    }

    @discardableResult
    func reorderSelected(_ order: AnnotationZOrder) -> Bool {
        guard selection.count == 1, let id = selection.primaryID,
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
