import Foundation

/// A reversible mutation of an EditorDocument.
protocol DocumentCommand {
    func apply(to document: EditorDocument)
    func revert(on document: EditorDocument)
    var name: String { get }
}

/// Command-pattern undo stack: every mutation is a DocumentCommand with an inverse.
final class UndoStack {
    static let depthLimit = 100
    private(set) var undoCommands: [DocumentCommand] = []
    private(set) var redoCommands: [DocumentCommand] = []

    var canUndo: Bool { !undoCommands.isEmpty }
    var canRedo: Bool { !redoCommands.isEmpty }

    func push(_ command: DocumentCommand, apply document: EditorDocument) {
        command.apply(to: document)
        undoCommands.append(command)
        if undoCommands.count > Self.depthLimit {
            undoCommands.removeFirst(undoCommands.count - Self.depthLimit)
        }
        redoCommands.removeAll()
    }

    func undo(on document: EditorDocument) {
        guard let command = undoCommands.popLast() else { return }
        command.revert(on: document)
        redoCommands.append(command)
    }

    func redo(on document: EditorDocument) {
        guard let command = redoCommands.popLast() else { return }
        command.apply(to: document)
        undoCommands.append(command)
    }
}

// MARK: - Concrete commands

struct AddAnnotationCommand: DocumentCommand {
    let annotation: Annotation
    var selectionBefore: AnnotationSelection = .empty
    var selectsAnnotation = false
    var name: String { "Add \(annotation.kind.rawValue)" }

    func apply(to document: EditorDocument) {
        document.annotations.append(annotation)
        if selectsAnnotation { document.selection = AnnotationSelection(orderedIDs: [annotation.id], primaryID: annotation.id) }
    }
    func revert(on document: EditorDocument) {
        document.annotations.removeAll { $0.id == annotation.id }
        if selectsAnnotation { document.selection = selectionBefore }
    }
}

struct AnnotationBatchCommand: DocumentCommand {
    let before: [Annotation]
    let after: [Annotation]
    let selectionBefore: AnnotationSelection
    let selectionAfter: AnnotationSelection
    let name: String

    func apply(to document: EditorDocument) {
        document.annotations = after
        document.selection = selectionAfter.normalized(for: after)
    }

    func revert(on document: EditorDocument) {
        document.annotations = before
        document.selection = selectionBefore.normalized(for: before)
    }
}

struct RemoveAnnotationCommand: DocumentCommand {
    let annotation: Annotation
    let index: Int
    var name: String { "Delete \(annotation.kind.rawValue)" }

    func apply(to document: EditorDocument) {
        document.annotations.removeAll { $0.id == annotation.id }
    }
    func revert(on document: EditorDocument) {
        document.annotations.insert(annotation, at: min(index, document.annotations.count))
    }
}

struct ModifyAnnotationCommand: DocumentCommand {
    let before: Annotation
    let after: Annotation
    var name: String { "Edit \(after.kind.rawValue)" }

    func apply(to document: EditorDocument) {
        if let idx = document.annotations.firstIndex(where: { $0.id == after.id }) {
            document.annotations[idx] = after
        }
    }
    func revert(on document: EditorDocument) {
        if let idx = document.annotations.firstIndex(where: { $0.id == before.id }) {
            document.annotations[idx] = before
        }
    }
}

struct ReorderAnnotationCommand: DocumentCommand {
    let annotationID: UUID
    let fromIndex: Int
    let toIndex: Int
    private(set) var name: String = "Reorder annotation"

    func apply(to document: EditorDocument) {
        guard let index = document.annotations.firstIndex(where: { $0.id == annotationID }),
              document.annotations.indices.contains(toIndex) else { return }
        let annotation = document.annotations.remove(at: index)
        document.annotations.insert(annotation, at: toIndex)
    }

    func revert(on document: EditorDocument) {
        guard let index = document.annotations.firstIndex(where: { $0.id == annotationID }),
              document.annotations.indices.contains(fromIndex) else { return }
        let annotation = document.annotations.remove(at: index)
        document.annotations.insert(annotation, at: fromIndex)
    }
}

struct SetCropCommand: DocumentCommand {
    let before: CGRect?
    let after: CGRect?
    var name: String { "Crop" }

    func apply(to document: EditorDocument) { document.cropRect = after }
    func revert(on document: EditorDocument) { document.cropRect = before }
}

struct SetStraightenCommand: DocumentCommand {
    let before: Double
    let after: Double
    var name: String { "Straighten" }

    func apply(to document: EditorDocument) { document.straightenDegrees = after }
    func revert(on document: EditorDocument) { document.straightenDegrees = before }
}

struct SetBeautifyCommand: DocumentCommand {
    let before: BeautifySettings
    let after: BeautifySettings
    var name: String { "Beautify" }

    func apply(to document: EditorDocument) { document.beautify = after }
    func revert(on document: EditorDocument) { document.beautify = before }
}

struct ApplyTemplateCommand: DocumentCommand {
    let annotations: [Annotation]
    var name: String { "Apply template" }

    func apply(to document: EditorDocument) {
        document.annotations.append(contentsOf: annotations)
    }

    func revert(on document: EditorDocument) {
        let ids = Set(annotations.map(\.id))
        document.annotations.removeAll { ids.contains($0.id) }
    }
}
