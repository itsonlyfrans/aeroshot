import Foundation

/// A reversible mutation of an EditorDocument.
protocol DocumentCommand {
    func apply(to document: EditorDocument)
    func revert(on document: EditorDocument)
    var name: String { get }
}

/// Command-pattern undo stack: every mutation is a DocumentCommand with an inverse.
final class UndoStack {
    private(set) var undoCommands: [DocumentCommand] = []
    private(set) var redoCommands: [DocumentCommand] = []

    var canUndo: Bool { !undoCommands.isEmpty }
    var canRedo: Bool { !redoCommands.isEmpty }

    func push(_ command: DocumentCommand, apply document: EditorDocument) {
        command.apply(to: document)
        undoCommands.append(command)
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
    var name: String { "Add \(annotation.kind.rawValue)" }

    func apply(to document: EditorDocument) {
        document.annotations.append(annotation)
    }
    func revert(on document: EditorDocument) {
        document.annotations.removeAll { $0.id == annotation.id }
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

struct SetCropCommand: DocumentCommand {
    let before: CGRect?
    let after: CGRect?
    var name: String { "Crop" }

    func apply(to document: EditorDocument) { document.cropRect = after }
    func revert(on document: EditorDocument) { document.cropRect = before }
}

struct SetBeautifyCommand: DocumentCommand {
    let before: BeautifySettings
    let after: BeautifySettings
    var name: String { "Beautify" }

    func apply(to document: EditorDocument) { document.beautify = after }
    func revert(on document: EditorDocument) { document.beautify = before }
}
