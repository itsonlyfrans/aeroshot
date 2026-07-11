import Combine
import Foundation

/// What the window should do when the user closes an editor.
nonisolated enum EditorCloseDecision: Equatable {
    /// Nothing worth persisting; close.
    case closeImmediately
    /// A project exists on disk; flush any pending autosave, then close.
    case flushAutosaveAndClose
    /// Unsaved work with no project on disk; ask before discarding.
    case promptForUnsavedWork
}

/// Owns the annotator's project-persistence state: the package URL, dirty
/// tracking, and the debounced autosave pipeline. Deliberately UI-free so the
/// save/autosave/reopen loop is testable without windows.
@MainActor
final class EditorProjectSession: ObservableObject {
    let document: EditorDocument
    @Published private(set) var packageURL: URL?
    /// True while edits exist that are not yet durably captured (saved or
    /// handed to a completed autosave write).
    @Published private(set) var isDirty = false
    @Published private(set) var lastAutosaveError: Error?

    private var manifest: AeroProjectManifest?
    private var autosave: AeroProjectAutosaveCoordinator?
    private let autosaveDebounce: Duration
    private var observers: Set<AnyCancellable> = []
    /// The undo tick captured by the most recent save or scheduled autosave.
    private var capturedUndoTick: Int

    init(
        document: EditorDocument,
        autosaveDebounce: Duration = .seconds(2)
    ) {
        self.document = document
        self.autosaveDebounce = autosaveDebounce
        self.capturedUndoTick = document.undoTick
        observeDocument()
    }

    static func openProject(
        at packageURL: URL,
        autosaveDebounce: Duration = .seconds(2)
    ) throws -> EditorProjectSession {
        let opened = try EditorProjectBridge.openWithManifest(from: packageURL)
        let session = EditorProjectSession(
            document: opened.document,
            autosaveDebounce: autosaveDebounce
        )
        session.adoptPackage(at: packageURL, manifest: opened.manifest)
        return session
    }

    var hasProjectURL: Bool { packageURL != nil }

    /// Full save through the bridge: creates the package on first save,
    /// validates and rewrites the manifest afterwards.
    @discardableResult
    func saveProject(to url: URL) throws -> AeroProjectManifest {
        let saved = try EditorProjectBridge.save(document, to: url)
        adoptPackage(at: url, manifest: saved)
        capturedUndoTick = document.undoTick
        isDirty = false
        return saved
    }

    @discardableResult
    func saveProject() throws -> AeroProjectManifest {
        guard let packageURL else {
            throw EditorWindowProjectError.projectHasNotBeenSaved
        }
        return try saveProject(to: packageURL)
    }

    func closeDecision() -> EditorCloseDecision {
        Self.closeDecision(hasProjectURL: hasProjectURL, isDirty: isDirty)
    }

    nonisolated static func closeDecision(
        hasProjectURL: Bool,
        isDirty: Bool
    ) -> EditorCloseDecision {
        switch (hasProjectURL, isDirty) {
        case (_, false): .closeImmediately
        case (true, true): .flushAutosaveAndClose
        case (false, true): .promptForUnsavedWork
        }
    }

    /// Writes the newest pending autosave snapshot immediately. Used by the
    /// close path so a debounce in flight never loses work.
    func flushPendingAutosave() async throws {
        guard let autosave else { return }
        _ = try await autosave.flushPendingSave()
        isDirty = false
    }

    private func adoptPackage(at url: URL, manifest: AeroProjectManifest) {
        self.manifest = manifest
        if packageURL != url {
            packageURL = url
            autosave = AeroProjectAutosaveCoordinator(
                store: AeroProjectPackageStore(packageURL: url),
                debounce: autosaveDebounce,
                onDebouncedSaveResult: { [weak self] result in
                    self?.handleAutosaveResult(result)
                }
            )
        }
    }

    private func observeDocument() {
        document.$undoTick
            .dropFirst()
            .sink { [weak self] _ in self?.documentDidChange() }
            .store(in: &observers)
        // Straighten currently bypasses the undo stack (slider writes the
        // published value directly), so it needs its own change signal to keep
        // autosave and the dirty flag honest.
        document.$straightenDegrees
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.documentDidChange() }
            .store(in: &observers)
    }

    private func documentDidChange() {
        isDirty = true
        guard autosave != nil, manifest != nil else { return }
        // @Published emits on willSet, so the property that triggered this
        // signal has not been written yet. Snapshot on the next main-actor
        // turn, after the mutation has landed.
        Task { @MainActor [weak self] in
            guard let self, let autosave = self.autosave, let manifest = self.manifest,
                  let updated = try? EditorProjectBridge.manifest(
                      byApplying: document, to: manifest
                  )
            else { return }
            capturedUndoTick = document.undoTick
            await autosave.projectDidChange(updated)
        }
    }

    private func handleAutosaveResult(_ result: Result<AeroProjectManifest, Error>) {
        switch result {
        case .success(let saved):
            manifest = saved
            lastAutosaveError = nil
            if document.undoTick == capturedUndoTick {
                isDirty = false
            }
        case .failure(let error):
            lastAutosaveError = error
        }
    }
}
