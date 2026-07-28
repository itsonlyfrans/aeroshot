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
        doc.selectOnly(annotation.id)
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
        doc.selectOnly(annotation.id)
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
        doc.selectOnly(annotation.id)
        #expect(!doc.nudgeSelected(by: .zero))
        #expect(!doc.undoStack.canUndo)
    }

    @Test func zOrderCommandsPreserveIDsAndUndoExactly() {
        let doc = document()
        let ids = [UUID(), UUID(), UUID()]
        doc.annotations = ids.map { Annotation(id: $0, kind: .line, points: [.zero, CGPoint(x: 2, y: 2)]) }
        doc.selectOnly(ids[0])
        #expect(doc.reorderSelected(.front))
        #expect(doc.annotations.map(\.id) == [ids[1], ids[2], ids[0]])
        doc.undo()
        #expect(doc.annotations.map(\.id) == ids)
        doc.redo()
        #expect(doc.annotations.map(\.id) == [ids[1], ids[2], ids[0]])
    }

    @Test func duplicateCreatesFreshTopmostOffsetCopyAndOneUndoStep() throws {
        let doc = document()
        var appearance = AnnotationAppearance()
        appearance.stroke.dash = [3, 5]
        appearance.fill.opacity = 0.4
        let original = Annotation(kind: .rectangle,
            points: [CGPoint(x: 10, y: 20), CGPoint(x: 40, y: 50)],
            color: .systemPurple, lineWidth: 7, filled: true, appearance: appearance)
        let other = Annotation(kind: .line, points: [.zero, CGPoint(x: 2, y: 2)])
        doc.annotations = [original, other]
        doc.selectOnly(original.id)

        let copy = try #require(doc.duplicateSelected().first)
        #expect(copy.id != original.id)
        #expect(copy.kind == original.kind)
        #expect(copy.color == original.color)
        #expect(copy.lineWidth == original.lineWidth)
        #expect(copy.filled == original.filled)
        #expect(copy.appearance == original.appearance)
        #expect(copy.points == original.points.map { CGPoint(x: $0.x + 12, y: $0.y + 12) })
        #expect(doc.annotations == [original, other, copy])
        #expect(doc.selection.primaryID == copy.id)
        #expect(doc.undoStack.undoCommands.count == 1)
        doc.undo()
        #expect(doc.annotations == [original, other])
        #expect(doc.selection.primaryID == original.id)
        doc.redo()
        #expect(doc.selection.primaryID == copy.id)
    }

    @Test func orderedSelectionToggleMarqueeAndSelectAllPreserveZOrder() {
        let doc = document()
        let first = Annotation(kind: .rectangle, points: [CGPoint(x: 5, y: 5), CGPoint(x: 20, y: 20)])
        let second = Annotation(kind: .rectangle, points: [CGPoint(x: 50, y: 50), CGPoint(x: 70, y: 70)])
        doc.annotations = [first, second]
        doc.toggleSelection(first.id)
        doc.toggleSelection(second.id)
        #expect(doc.selection.orderedIDs == [first.id, second.id])
        doc.toggleSelection(first.id)
        doc.toggleSelection(first.id)
        #expect(doc.selection.orderedIDs == [first.id, second.id])
        #expect(doc.selection.primaryID == first.id)
        doc.toggleSelection(second.id)
        #expect(doc.selection == AnnotationSelection(orderedIDs: [first.id], primaryID: first.id))
        doc.selection = AnnotationSelectionController.marqueeSelection(
            in: CGRect(x: 0, y: 0, width: 30, height: 30), annotations: doc.annotations
        )
        #expect(doc.selection.orderedIDs == [first.id])
        doc.selectAll()
        #expect(doc.selection.orderedIDs == [first.id, second.id])
    }

    @Test func groupNudgeDeleteDuplicateAreAtomicAndRestoreSelection() {
        let doc = document()
        let first = Annotation(kind: .line, points: [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20)])
        let second = Annotation(kind: .line, points: [CGPoint(x: 80, y: 80), CGPoint(x: 90, y: 90)])
        doc.annotations = [first, second]
        doc.selection = AnnotationSelection(orderedIDs: [first.id, second.id], primaryID: first.id)
        #expect(doc.nudgeSelected(by: CGPoint(x: 20, y: 20)))
        let firstDelta = (doc.annotation(withID: first.id)?.points.first?.x ?? 0) - first.points[0].x
        let secondDelta = (doc.annotation(withID: second.id)?.points.first?.x ?? 0) - second.points[0].x
        #expect(firstDelta == secondDelta)
        #expect(AnnotationSelectionController.bounds(of: doc.selectedAnnotations)?.maxX ?? .infinity <= doc.pixelSize.width)
        doc.undo()
        #expect(doc.annotations == [first, second])
        #expect(doc.selection.primaryID == first.id)
        let copies = doc.duplicateSelected()
        #expect(copies.count == 2)
        #expect(doc.annotations.map(\.id) == [first.id, second.id] + copies.map(\.id))
        doc.undo()
        #expect(doc.annotations == [first, second])
        #expect(doc.deleteSelected())
        #expect(doc.annotations.isEmpty)
        doc.undo()
        #expect(doc.annotations == [first, second])
        #expect(doc.selection.orderedIDs == [first.id, second.id])
    }

    @Test func groupTranslationNeverMovesAnUnrequestedAxisOrOpposesOverflowDirection() {
        let line = Annotation(kind: .line, points: [CGPoint(x: -5, y: -5), CGPoint(x: 20, y: 20)])
        let horizontal = AnnotationSelectionController.commonTranslation(
            for: [line], requested: CGPoint(x: 4, y: 0), within: CGSize(width: 100, height: 100)
        )
        #expect(horizontal == CGPoint(x: 4, y: 0))
        let outward = AnnotationSelectionController.commonTranslation(
            for: [line], requested: CGPoint(x: -1, y: 0), within: CGSize(width: 100, height: 100)
        )
        #expect(outward == .zero)
    }

    @Test func annotationPasteboardCodecRoundTripsLosslesslyAndPasteGetsFreshID() throws {
        let doc = document()
        var appearance = AnnotationAppearance()
        appearance.stroke.shadow.color = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        appearance.typography.backgroundColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        appearance.typography.backgroundOpacity = 0.5
        let original = Annotation(kind: .text, points: [CGPoint(x: 20, y: 30)],
                                  color: NSColor(srgbRed: 0, green: 0.5, blue: 1, alpha: 1),
                                  text: "Across windows", fontSize: 31, appearance: appearance)
        let data = try AnnotationPasteboardCodec.encode(original, imageSize: doc.pixelSize)
        let decoded = try AnnotationPasteboardCodec.decode(data)
        #expect(decoded == original)
        let pasted = doc.insertCopy(of: decoded)
        #expect(pasted.id != original.id)
        #expect(pasted.text == original.text)
        #expect(pasted.appearance == original.appearance)
        #expect(doc.undoStack.undoCommands.count == 1)
        #expect((try? AnnotationPasteboardCodec.decode(Data("not-json".utf8))) == nil)

        var malformedJSON = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var malformedOverlay = try #require(malformedJSON["overlay"] as? [String: Any])
        var invalidAppearance = try #require(malformedOverlay["appearance"] as? [String: Any])
        invalidAppearance["strokeRGBA"] = [2, -1, 0, 1]
        invalidAppearance["strokeWidth"] = -4
        malformedOverlay["appearance"] = invalidAppearance
        malformedJSON["overlay"] = malformedOverlay
        #expect((try? AnnotationPasteboardCodec.decode(JSONSerialization.data(withJSONObject: malformedJSON))) == nil)

        var inconsistentJSON = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var inconsistentOverlay = try #require(inconsistentJSON["overlay"] as? [String: Any])
        var geometry = try #require(inconsistentOverlay["geometry"] as? [String: Any])
        geometry["points"] = [["x": 99.0, "y": 99.0]]
        inconsistentOverlay["geometry"] = geometry
        inconsistentJSON["overlay"] = inconsistentOverlay
        #expect((try? AnnotationPasteboardCodec.decode(JSONSerialization.data(withJSONObject: inconsistentJSON))) == nil)
    }

    @Test func annotationPasteboardCodecRejectsOversizedUntrustedPayloads() throws {
        #expect(throws: AnnotationPasteboardCodecError.invalidPayload) {
            try AnnotationPasteboardCodec.decode(
                Data(count: AnnotationPasteboardCodec.maximumPayloadByteCount + 1)
            )
        }

        let original = Annotation(kind: .text, points: [CGPoint(x: 20, y: 30)], text: "Safe")
        let data = try AnnotationPasteboardCodec.encode(original, imageSize: CGSize(width: 100, height: 100))
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var overlay = try #require(json["overlay"] as? [String: Any])
        var editor = try #require(overlay["editor"] as? [String: Any])
        editor["text"] = String(repeating: "x", count: AnnotationPasteboardCodec.maximumTextByteCount + 1)
        overlay["editor"] = editor
        json["overlay"] = overlay

        #expect(throws: AnnotationPasteboardCodecError.invalidPayload) {
            try AnnotationPasteboardCodec.decode(JSONSerialization.data(withJSONObject: json))
        }

        editor["text"] = "Safe"
        overlay["editor"] = editor
        var geometry = try #require(overlay["geometry"] as? [String: Any])
        geometry["points"] = Array(
            repeating: ["x": 20.0, "y": 30.0],
            count: AnnotationPasteboardCodec.maximumPointCount + 1
        )
        overlay["geometry"] = geometry
        json["overlay"] = overlay
        #expect(throws: AnnotationPasteboardCodecError.invalidPayload) {
            try AnnotationPasteboardCodec.decode(JSONSerialization.data(withJSONObject: json))
        }

        geometry["points"] = [["x": 20.0, "y": 30.0]]
        overlay["geometry"] = geometry
        var appearance = try #require(editor["appearance"] as? [String: Any])
        appearance["strokeDash"] = Array(
            repeating: 1.0,
            count: AnnotationPasteboardCodec.maximumDashCount + 1
        )
        editor["appearance"] = appearance
        overlay["editor"] = editor
        json["overlay"] = overlay
        #expect(throws: AnnotationPasteboardCodecError.invalidPayload) {
            try AnnotationPasteboardCodec.decode(JSONSerialization.data(withJSONObject: json))
        }
    }

    @Test func textReeditCommitsOneModifyCommandAndBlankOrNoopDoesNothing() {
        let doc = document()
        let original = Annotation(kind: .text, points: [CGPoint(x: 10, y: 10)], text: "Before")
        doc.annotations = [original]
        #expect(doc.editTextAnnotation(id: original.id, text: "After"))
        #expect(doc.annotation(withID: original.id)?.text == "After")
        #expect(doc.undoStack.undoCommands.count == 1)
        doc.undo()
        #expect(doc.annotation(withID: original.id) == original)
        #expect(!doc.editTextAnnotation(id: original.id, text: "   "))
        #expect(!doc.editTextAnnotation(id: original.id, text: "Before"))
        #expect(!doc.undoStack.canUndo)
    }

    @Test func textReeditPreservesIntentionalWhitespaceWhenUnchanged() {
        let doc = document()
        let original = Annotation(kind: .text, points: [CGPoint(x: 10, y: 10)], text: "  padded  ")
        doc.annotations = [original]
        #expect(!doc.editTextAnnotation(id: original.id, text: original.text))
        #expect(doc.annotation(withID: original.id) == original)
        #expect(!doc.undoStack.canUndo)
    }

    @Test func oversizedCrossWindowPasteIsTranslatedIntoVisibleCanvasArea() {
        let doc = document()
        let source = Annotation(kind: .rectangle,
            points: [CGPoint(x: 200, y: 20), CGPoint(x: 400, y: 80)])
        let pasted = doc.insertCopy(of: source)
        #expect(pasted.boundingRect.intersects(CGRect(origin: .zero, size: doc.pixelSize)))
        doc.undo()
        #expect(doc.annotations.isEmpty)
        #expect(doc.selection.isEmpty)
    }

    @Test func partiallyOffCanvasAnnotationStillRoundTripsThroughClipboard() throws {
        let doc = document()
        var appearance = AnnotationAppearance()
        appearance.stroke.shadow.color = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let original = Annotation(kind: .rectangle,
            points: [CGPoint(x: 80, y: 70), CGPoint(x: 130, y: 120)],
            color: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), appearance: appearance)
        let data = try AnnotationPasteboardCodec.encode(original, imageSize: doc.pixelSize)
        #expect(try AnnotationPasteboardCodec.decode(data) == original)

        let vertical = Annotation(kind: .rectangle,
            points: [CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 90)],
            color: original.color, appearance: appearance)
        #expect(try AnnotationPasteboardCodec.decode(
            AnnotationPasteboardCodec.encode(vertical, imageSize: doc.pixelSize)
        ) == vertical)
    }

    @Test func toolKeymapIsUniqueCompleteAndRejectsModifiedTyping() {
        #expect(Set(EditorToolKeymap.shortcuts.map(\.key)).count == EditorToolKeymap.shortcuts.count)
        #expect(EditorToolKeymap.tool(for: "V") == .select)
        #expect(EditorToolKeymap.tool(for: "a") == .arrow)
        #expect(EditorToolKeymap.tool(for: "r") == .rectangle)
        #expect(EditorToolKeymap.tool(for: "t") == .text)
        #expect(EditorToolKeymap.tool(for: "h") == .pan)
        #expect(EditorToolKeymap.tool(for: "t", modifiers: .command) == nil)
        #expect(EditorToolKeymap.tool(for: "?", modifiers: []) == nil)
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
