import AppKit
import Testing
@testable import Aeroshot

@MainActor
struct AnnotationInspectorTests {
    @Test func validatedNumericValuesClampAndRejectNonFiniteInput() {
        #expect(AnnotationInspectorController.validated(99, for: .strokeWidth) == 64)
        #expect(AnnotationInspectorController.validated(-1, for: .opacity) == 0)
        #expect(AnnotationInspectorController.validated(.nan, for: .arrowLength) == nil)
        #expect(AnnotationInspectorController.validated(7.26, for: .strokeWidth, step: true) == 7.5)
    }

    @Test func selectedMutationCreatesOneExactUndoCommand() throws {
        let document = EditorDocument(image: makeImage())
        let original = Annotation(kind: .arrow, points: [.zero, CGPoint(x: 40, y: 20)])
        document.annotations = [original]
        document.selectOnly(original.id)
        let controller = AnnotationInspectorController(document: document)

        #expect(controller.update(.arrowLength, value: 22.5))
        #expect(try #require(document.annotation(withID: original.id)?.appearance.arrow.headLength) == 22.5)
        #expect(document.undoStack.undoCommands.count == 1)
        document.undo()
        #expect(document.annotation(withID: original.id) == original)
        document.redo()
        #expect(document.annotation(withID: original.id)?.appearance.arrow.headLength == 22.5)
    }

    @Test func everyNumericPropertyMapsToSharedAppearance() throws {
        let document = EditorDocument(image: makeImage())
        let original = Annotation(kind: .text, points: [.zero])
        document.annotations = [original]
        document.selectOnly(original.id)
        let controller = AnnotationInspectorController(document: document)

        for (property, value) in [
            (.strokeWidth, 8), (.opacity, 0.5), (.fillOpacity, 0.4),
            (.dashLength, 6), (.dashGap, 3), (.dashPhase, 1),
            (.arrowLength, 18), (.arrowWidth, 9), (.arrowInset, 5),
            (.arrowCurve, -12), (.cornerRadius, 11), (.shadowOpacity, 0.3),
            (.shadowRadius, 7), (.shadowOffsetX, -2), (.shadowOffsetY, 4),
            (.fontSize, 30), (.textBackgroundOpacity, 0.6),
            (.textPadding, 8), (.textLineHeight, 1.4),
        ] as [(AnnotationInspectorNumericProperty, Double)] {
            #expect(controller.update(property, value: value))
        }

        let updated = try #require(document.annotation(withID: original.id))
        #expect(updated.lineWidth == 8)
        #expect(updated.appearance.stroke.opacity == 0.5)
        #expect(updated.appearance.fill.opacity == 0.4)
        #expect(updated.appearance.stroke.dash == [6, 3])
        #expect(updated.appearance.arrow.headLength == 18)
        #expect(updated.appearance.arrow.headWidth == 9)
        #expect(updated.appearance.arrow.inset == 5)
        #expect(updated.appearance.arrow.curve == -12)
        #expect(updated.appearance.cornerRadius == 11)
        #expect(updated.appearance.stroke.shadow.offset == CGSize(width: -2, height: 4))
        #expect(updated.fontSize == 30)
        #expect(updated.appearance.typography.padding == AnnotationInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        #expect(updated.appearance.typography.lineHeight == 1.4)
    }

    @Test func noSelectionNeverOverwritesAnnotations() {
        let document = EditorDocument(image: makeImage())
        let annotation = Annotation(kind: .rectangle)
        document.annotations = [annotation]
        let controller = AnnotationInspectorController(document: document)

        #expect(!controller.update(.strokeWidth, value: 12))
        #expect(document.annotations == [annotation])
        #expect(!document.undoStack.canUndo)
    }

    @Test func homogeneousSelectionEditsAtomicallyAndMixedKindsAreReported() {
        let document = EditorDocument(image: makeImage())
        let first = Annotation(kind: .rectangle, points: [.zero, CGPoint(x: 10, y: 10)])
        let second = Annotation(kind: .rectangle, points: [CGPoint(x: 20, y: 20), CGPoint(x: 30, y: 30)])
        document.annotations = [first, second]
        document.selection = AnnotationSelection(orderedIDs: [first.id, second.id], primaryID: second.id)
        let controller = AnnotationInspectorController(document: document)
        #expect(!controller.hasMixedKinds)
        #expect(controller.update(.strokeWidth, value: 9))
        #expect(document.annotations.allSatisfy { $0.lineWidth == 9 })
        #expect(document.undoStack.undoCommands.count == 1)
        document.undo()
        #expect(document.annotations == [first, second])

        document.annotations[1] = Annotation(kind: .text, points: [CGPoint(x: 20, y: 20)])
        document.selection = AnnotationSelection(orderedIDs: document.annotations.map(\.id), primaryID: document.annotations.last?.id)
        #expect(AnnotationInspectorController(document: document).hasMixedKinds)
    }

    @Test func selectionPolicyIsPureForDefaultsHomogeneousAndMixedKinds() {
        let first = Annotation(kind: .rectangle, points: [.zero, CGPoint(x: 10, y: 10)])
        var second = Annotation(kind: .rectangle, points: [CGPoint(x: 20, y: 20), CGPoint(x: 30, y: 30)])
        #expect(AnnotationInspectorSelectionPolicy.resolve([]) == .defaults)
        #expect(AnnotationInspectorSelectionPolicy.resolve([first, second]) == .homogeneous(kind: .rectangle, count: 2, hasMixedValues: false))
        second.lineWidth = 9
        #expect(AnnotationInspectorSelectionPolicy.resolve([first, second]) == .homogeneous(kind: .rectangle, count: 2, hasMixedValues: true))
        let text = Annotation(kind: .text, points: [.zero])
        #expect(AnnotationInspectorSelectionPolicy.resolve([first, text]) == .mixedKinds(count: 2))
    }

    @Test func mixedValuesAreDetectedPerPropertyAndArrowheadEditsStayScoped() {
        let document = EditorDocument(image: makeImage())
        var first = Annotation(kind: .arrow, points: [.zero, CGPoint(x: 20, y: 20)])
        var second = Annotation(kind: .arrow, points: [CGPoint(x: 30, y: 30), CGPoint(x: 50, y: 50)])
        first.appearance.arrow.endStyle = .open
        second.appearance.arrow.startStyle = .open
        second.appearance.arrow.endStyle = .filled
        document.annotations = [first, second]
        document.selection = AnnotationSelection(orderedIDs: [first.id, second.id], primaryID: first.id)
        let controller = AnnotationInspectorController(document: document)
        #expect(!controller.valuesMatch { $0.appearance.arrow.startStyle })
        #expect(!controller.valuesMatch { $0.appearance.arrow.endStyle })
        #expect(controller.updateArrowhead(.none, start: true))
        #expect(document.annotations.allSatisfy { $0.appearance.arrow.startStyle == .none })
        #expect(document.annotations.map { $0.appearance.arrow.endStyle } == [.open, .filled])
    }

    @Test func enumAndTextEditsAreUndoableAndSelectionScoped() throws {
        let document = EditorDocument(image: makeImage())
        let first = Annotation(kind: .arrow, text: "First")
        let second = Annotation(kind: .text, text: "Second")
        document.annotations = [first, second]
        document.selectOnly(second.id)
        let controller = AnnotationInspectorController(document: document)

        #expect(controller.updateText("Edited"))
        #expect(controller.updateTextAlignment(.center))
        #expect(controller.updateArrowheads(start: .open, end: .none))
        #expect(document.annotation(withID: first.id) == first)
        #expect(document.annotation(withID: second.id)?.text == "Edited")
        #expect(document.annotation(withID: second.id)?.appearance.typography.alignment == .center)
        #expect(document.annotation(withID: second.id)?.appearance.arrow.startStyle == .open)
    }

    private func makeImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
