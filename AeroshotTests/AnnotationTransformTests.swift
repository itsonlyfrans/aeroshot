import AppKit
import Testing
@testable import Aeroshot

@MainActor
struct AnnotationTransformTests {
    private func document(size: Int = 100) -> EditorDocument {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return EditorDocument(image: context.makeImage()!)
    }

    @Test func handleHitUsesToolGeometryAndStableID() {
        let id = UUID()
        let line = Annotation(id: id, kind: .line, points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)])
        #expect(AnnotationSelectionController.handleHit(at: CGPoint(x: 12, y: 10), annotation: line, tolerance: 3) == .init(annotationID: id, index: 0))
        #expect(AnnotationSelectionController.handleHit(at: CGPoint(x: 50, y: 50), annotation: line, tolerance: 3) == nil)
    }

    @Test func resizeEndpointsAndBoundingObjectsAreDeterministic() {
        let line = Annotation(kind: .line, points: [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20)])
        #expect(AnnotationSelectionController.resized(line, handleIndex: 1, to: CGPoint(x: 150, y: -10), within: CGSize(width: 100, height: 100)).points[1] == CGPoint(x: 100, y: 0))
        let rect = Annotation(kind: .rectangle, points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 40)])
        let resized = AnnotationSelectionController.resized(rect, handleIndex: 0, to: CGPoint(x: 29.8, y: 39.8), within: CGSize(width: 100, height: 100))
        #expect(resized.boundingRect.width >= 1)
        #expect(resized.boundingRect.height >= 1)
    }

    @Test func nudgeClampUndoRedoAndRedoInvalidation() {
        let doc = document()
        let annotation = Annotation(kind: .rectangle, points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 30)])
        doc.perform(AddAnnotationCommand(annotation: annotation))
        doc.selectedAnnotationID = annotation.id
        #expect(doc.nudgeSelected(by: CGPoint(x: 1, y: -1)))
        #expect(doc.annotation(withID: annotation.id)?.points[0] == CGPoint(x: 11, y: 9))
        doc.undo()
        #expect(doc.annotation(withID: annotation.id) == annotation)
        doc.redo()
        #expect(doc.annotation(withID: annotation.id)?.points[0] == CGPoint(x: 11, y: 9))
        doc.undo()
        #expect(doc.nudgeSelected(by: CGPoint(x: 10, y: 0)))
        #expect(!doc.undoStack.canRedo)
    }

    @Test func keyboardUnitAndAcceleratedDeltasRemainExact() {
        let doc = document()
        let annotation = Annotation(kind: .line, points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])
        doc.annotations = [annotation]
        doc.selectedAnnotationID = annotation.id
        #expect(doc.nudgeSelected(by: CGPoint(x: 1, y: 0)))
        #expect(doc.nudgeSelected(by: CGPoint(x: 0, y: 10)))
        #expect(doc.annotation(withID: annotation.id)?.points == [CGPoint(x: 21, y: 30), CGPoint(x: 41, y: 50)])
        doc.undo()
        doc.undo()
        #expect(doc.annotation(withID: annotation.id) == annotation)
    }

    @Test func resizeCommitsAsOneExactUndoableCommand() {
        let doc = document()
        let original = Annotation(kind: .ellipse, points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 30)])
        doc.annotations = [original]
        let resized = AnnotationSelectionController.resized(original, handleIndex: 2, to: CGPoint(x: 70, y: 80), within: doc.pixelSize)
        #expect(doc.transformAnnotation(id: original.id, to: resized))
        #expect(doc.undoStack.undoCommands.count == 1)
        doc.undo()
        #expect(doc.annotation(withID: original.id) == original)
        doc.redo()
        #expect(doc.annotation(withID: original.id) == resized)
    }

    @Test func noOpTransformDoesNotCreateUndoEntry() {
        let doc = document()
        let annotation = Annotation(kind: .line, points: [.zero, CGPoint(x: 10, y: 10)])
        doc.annotations = [annotation]
        doc.selectedAnnotationID = annotation.id
        #expect(!doc.nudgeSelected(by: .zero))
        #expect(!doc.undoStack.canUndo)
    }

    @Test func zOrderCommandsPreserveIDsAndUndoExactly() {
        let doc = document()
        let ids = [UUID(), UUID(), UUID()]
        doc.annotations = ids.map { Annotation(id: $0, kind: .line, points: [.zero, CGPoint(x: 2, y: 2)]) }
        doc.selectedAnnotationID = ids[0]
        #expect(doc.reorderSelected(.front))
        #expect(doc.annotations.map(\.id) == [ids[1], ids[2], ids[0]])
        doc.undo()
        #expect(doc.annotations.map(\.id) == ids)
        doc.redo()
        #expect(doc.annotations.map(\.id) == [ids[1], ids[2], ids[0]])
    }

    @Test func cropDraftRequiresExplicitApplyAndCanCancel() {
        let doc = document()
        let draft = CGRect(x: 10, y: 15, width: 60, height: 45)
        doc.pendingCropRect = draft
        #expect(doc.cropRect == nil)
        doc.cancelPendingCrop()
        #expect(doc.pendingCropRect == nil)
        doc.pendingCropRect = draft
        doc.applyPendingCrop()
        #expect(doc.cropRect == draft)
        #expect(doc.undoStack.canUndo)
        doc.undo()
        #expect(doc.cropRect == nil)
    }
}
