import Foundation

actor AeroProjectAutosaveCoordinator {
    private let store: AeroProjectPackageStore
    private let debounce: Duration
    private var pendingManifest: AeroProjectManifest?
    private var saveTask: Task<Void, Never>?
    private(set) var lastSaveError: Error?

    init(store: AeroProjectPackageStore, debounce: Duration = .seconds(2)) {
        self.store = store
        self.debounce = debounce
    }

    deinit {
        saveTask?.cancel()
    }

    func projectDidChange(_ manifest: AeroProjectManifest) {
        pendingManifest = manifest
        saveTask?.cancel()
        let delay = debounce
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                _ = try await self?.flushPendingSave()
            } catch is CancellationError {
                return
            } catch {
                await self?.record(error)
            }
        }
    }

    /// Saves the newest pending snapshot immediately. This is used for app
    /// lifecycle flushes and makes debounce behavior deterministic in tests.
    @discardableResult
    func flushPendingSave() throws -> AeroProjectManifest? {
        saveTask?.cancel()
        saveTask = nil
        guard let manifest = pendingManifest else { return nil }
        pendingManifest = nil
        do {
            let saved = try store.save(manifest)
            lastSaveError = nil
            return saved
        } catch {
            pendingManifest = manifest
            lastSaveError = error
            throw error
        }
    }

    func cancelPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        pendingManifest = nil
    }

    private func record(_ error: Error) {
        lastSaveError = error
    }
}
