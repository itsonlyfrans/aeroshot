import Foundation
import os

actor AeroProjectAutosaveCoordinator {
    private let store: AeroProjectPackageStore
    private let debounce: Duration
    private var pendingManifest: AeroProjectManifest?
    private var saveTask: Task<Void, Never>?
    private(set) var lastSaveError: Error?
    private let onDebouncedSaveResult: (@MainActor @Sendable (Result<AeroProjectManifest, Error>) -> Void)?

    /// `onDebouncedSaveResult` reports the outcome of each debounced save on
    /// the main actor. It is part of the initializer so no debounced save can
    /// fire before the handler exists. Manual `flushPendingSave` callers
    /// already observe results via return/throw.
    init(
        store: AeroProjectPackageStore,
        debounce: Duration = .seconds(2),
        onDebouncedSaveResult: (@MainActor @Sendable (Result<AeroProjectManifest, Error>) -> Void)? = nil
    ) {
        self.store = store
        self.debounce = debounce
        self.onDebouncedSaveResult = onDebouncedSaveResult
    }

    deinit {
        saveTask?.cancel()
    }

    func projectDidChange(_ manifest: AeroProjectManifest) {
        let editState = PerformanceInstrumentation.signposter.beginInterval("AutosaveLastEdit")
        pendingManifest = manifest
        PerformanceInstrumentation.signposter.endInterval("AutosaveLastEdit", editState)
        let scheduleState = PerformanceInstrumentation.signposter.beginInterval("AutosaveSchedule")
        saveTask?.cancel()
        let delay = debounce
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                if let saved = try await self?.flushPendingSave() {
                    await self?.report(.success(saved))
                }
            } catch is CancellationError {
                return
            } catch {
                await self?.record(error)
                await self?.report(.failure(error))
            }
        }
        PerformanceInstrumentation.signposter.endInterval("AutosaveSchedule", scheduleState)
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

    private func report(_ result: Result<AeroProjectManifest, Error>) {
        guard let handler = onDebouncedSaveResult else { return }
        Task { @MainActor in
            let state = PerformanceInstrumentation.signposter.beginInterval("AutosaveMainActorPublish")
            handler(result)
            PerformanceInstrumentation.signposter.endInterval("AutosaveMainActorPublish", state)
        }
    }
}
