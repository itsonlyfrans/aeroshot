import AppKit
import Foundation
import Testing
@testable import Aeroshot

@Suite(.serialized)
@MainActor
struct EditorProjectSessionTests {
    @Test func closeDecisionMatrixIsExhaustiveAndHonest() {
        #expect(EditorProjectSession.closeDecision(hasProjectURL: false, isDirty: false) == .closeImmediately)
        #expect(EditorProjectSession.closeDecision(hasProjectURL: true, isDirty: false) == .closeImmediately)
        #expect(EditorProjectSession.closeDecision(hasProjectURL: true, isDirty: true) == .flushAutosaveAndClose)
        #expect(EditorProjectSession.closeDecision(hasProjectURL: false, isDirty: true) == .promptForUnsavedWork)
    }

    @Test func mutationsAutosaveAndReopenIdentically() async throws {
        try await withPackage { packageURL in
            let session = EditorProjectSession(
                document: EditorDocument(image: makeImage()),
                autosaveDebounce: .milliseconds(20)
            )
            try session.saveProject(to: packageURL)
            #expect(!session.isDirty)

            let annotation = makeAnnotation()
            session.document.perform(AddAnnotationCommand(annotation: annotation))
            session.document.perform(SetCropCommand(before: nil, after: CGRect(x: 1, y: 1, width: 2, height: 1)))
            session.document.straightenDegrees = 3.5
            #expect(session.isDirty)

            try await waitUntil { !session.isDirty }
            #expect(session.lastAutosaveError == nil)

            let reopened = try EditorProjectBridge.open(from: packageURL)
            #expect(reopened.annotations == [annotation])
            #expect(reopened.cropRect == CGRect(x: 1, y: 1, width: 2, height: 1))
            #expect(reopened.straightenDegrees == 3.5)
        }
    }

    @Test func flushPendingAutosavePersistsWithoutWaitingForDebounce() async throws {
        try await withPackage { packageURL in
            let session = EditorProjectSession(
                document: EditorDocument(image: makeImage()),
                autosaveDebounce: .seconds(60)
            )
            try session.saveProject(to: packageURL)
            let annotation = makeAnnotation()
            session.document.perform(AddAnnotationCommand(annotation: annotation))
            #expect(session.isDirty)

            // Scheduling reaches the coordinator through an actor hop; give it
            // a beat before flushing so the pending manifest is registered.
            try await waitUntilFlushed(session) {
                try EditorProjectBridge.open(from: packageURL).annotations == [annotation]
            }
            #expect(!session.isDirty)
        }
    }

    @Test func dirtyTrackingFollowsUndoRedoAndSaves() async throws {
        try await withPackage { packageURL in
            let session = EditorProjectSession(
                document: EditorDocument(image: makeImage()),
                autosaveDebounce: .seconds(60)
            )
            #expect(!session.isDirty)
            #expect(!session.hasProjectURL)

            session.document.perform(AddAnnotationCommand(annotation: makeAnnotation()))
            #expect(session.isDirty)
            #expect(session.closeDecision() == .promptForUnsavedWork)

            try session.saveProject(to: packageURL)
            #expect(!session.isDirty)
            #expect(session.hasProjectURL)
            #expect(session.closeDecision() == .closeImmediately)

            session.document.undo()
            #expect(session.isDirty)
            #expect(session.closeDecision() == .flushAutosaveAndClose)
        }
    }

    @Test func savingWithoutAProjectURLThrows() throws {
        let session = EditorProjectSession(document: EditorDocument(image: makeImage()))
        #expect(throws: EditorWindowProjectError.projectHasNotBeenSaved) {
            try session.saveProject()
        }
    }

    // MARK: - Helpers

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for autosave")
    }

    private func waitUntilFlushed(
        _ session: EditorProjectSession,
        verify: @escaping @MainActor () throws -> Bool
    ) async throws {
        for _ in 0..<400 {
            try await session.flushPendingAutosave()
            if try verify() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for flushed autosave")
    }

    private func makeAnnotation() -> Annotation {
        Annotation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: .rectangle,
            points: [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 2.5, y: 2.25)],
            color: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1),
            lineWidth: 3,
            text: "",
            fontSize: 24,
            stepNumber: 0,
            filled: false,
            // The bridge canonicalizes persisted colors to sRGB, so the
            // fixture's shadow color starts there for exact reopen equality.
            appearance: AnnotationAppearance(
                stroke: AnnotationStrokeAppearance(
                    shadow: AnnotationShadow(
                        color: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
                    )
                )
            )
        )
    }

    private func makeImage() -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: 4,
            height: 3,
            bitsPerComponent: 8,
            bytesPerRow: 4 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        return context.makeImage()!
    }

    private func withPackage(_ body: (URL) async throws -> Void) async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "EditorProjectSessionTests-\(UUID().uuidString).aeroshot")
        defer { try? FileManager.default.removeItem(at: url) }
        try await body(url)
    }
}
