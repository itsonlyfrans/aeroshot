import AppKit
import Foundation
import ScreenCaptureKit
import Testing
@testable import Aeroshot

@MainActor
struct RecordingControllerIntegrationTests {
    @Test func preflightBlocksDeniedPermissionAndLowSpaceDeterministically() throws {
        let configuration = try fixtureConfiguration(requiredSpace: 1_000)
        let denied = RecordingPreflightModel(
            configuration: configuration,
            readiness: RecordingPreflightReadiness(
                permissionStatuses: [.screenRecording: .denied], availableSpaceBytes: 2_000
            )
        )
        #expect(!denied.isReady)
        #expect(denied.blockingMessage == "Screen Recording permission is required.")

        let lowSpace = RecordingPreflightModel(
            configuration: configuration,
            readiness: RecordingPreflightReadiness(
                permissionStatuses: [.screenRecording: .granted], availableSpaceBytes: 999
            )
        )
        #expect(!lowSpace.isReady)
        #expect(lowSpace.blockingMessage == "Not enough free space to start recording.")
    }

    @Test func hudExposesExplicitPauseResumeStopAndCancelActions() {
        let model = HUDToolbarModel(
            selected: .area,
            options: HUDRecordingOptions(
                microphoneEnabled: false,
                systemAudioEnabled: false,
                cameraEnabled: false,
                countdownSeconds: 0
            )
        )
        var events: [String] = []
        model.onPauseResume = { events.append("pause") }
        model.onStop = { events.append("stop") }
        model.onCancel = { events.append("cancel") }
        model.onPauseResume?()
        model.onStop?()
        model.onCancel?()
        #expect(events == ["pause", "stop", "cancel"])
    }

    @Test func injectedCaptureServiceReceivesPauseResumeAndCancelWithoutPermissions() async {
        let service = FakeRecordingService()
        #expect(service.pause())
        #expect(service.resume())
        await service.cancel()
        #expect(service.events == ["pause", "resume", "cancel"])
    }

    @Test func repeatedStopAndCancelJoinTheFirstSuccessfulTerminalOperation() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RecordingTerminal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appending(path: "capture.mp4")
        try Data("video".utf8).write(to: output)
        let service = TerminalRecordingService(outputURL: output)
        let appState = AppState()
        let controller = RecordingController(appState: appState, session: try activeSession())
        controller.installRecordingForTesting(recorder: service, outputURL: output)

        let first = Task { await controller.stopRecording(save: true) }
        await service.waitUntilStopping()
        let second = Task { await controller.stopRecording(save: false) }
        await Task.yield()
        #expect(service.stopCalls == 1)
        #expect(service.cancelCalls == 0)

        await service.finishStop()
        await first.value
        await second.value

        await controller.stopRecording(save: false)

        #expect(service.stopCalls == 1)
        #expect(service.cancelCalls == 0)
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test func gifDiscardStopsFrameAcceptanceAndClearsItsSpool() async throws {
        let service = GIFRecordingService(maxFrames: 1)
        try service.beginCapture(fps: 10)
        #expect(service.acceptsFrames)
        #expect(service.hasBufferedFrames)

        await service.cancel()

        #expect(!service.acceptsFrames)
        #expect(!service.hasBufferedFrames)
    }

    @Test func cancellationRejectsLateCaptureStartBeforeItCanRetainTheStream() {
        let gate = CaptureStartGate<String>()
        let generation = gate.beginStartOperation()

        #expect(gate.invalidate() == nil)
        #expect(!gate.complete("late stream", for: generation))
        #expect(gate.invalidate() == nil)
        gate.startOperationDidFinish()
    }

    @Test func concurrentRecordingStartsKeepOneOwnerAndReleaseIt() async {
        let gate = CaptureStartGate<Void>()
        let permission = AsyncTestGate()
        let starts = StartCounter()

        let first = Task { () -> Bool in
            guard let generation = gate.tryBeginStartOperation() else { return false }
            defer { gate.startOperationDidFinish() }
            await permission.wait()
            guard gate.isActive(for: generation) else { return false }
            await starts.record()
            _ = gate.invalidate()
            return true
        }
        await permission.waitUntilStarted()

        #expect(gate.tryBeginStartOperation() == nil)

        await permission.resume()
        #expect(await first.value)
        #expect(await starts.value == 1)

        let later = gate.tryBeginStartOperation()
        #expect(later != nil)
        _ = gate.invalidate()
        gate.startOperationDidFinish()
    }

    @Test func cancelledPendingStartBlocksRetryUntilItsCleanupFinishes() async throws {
        let gate = CaptureStartGate<Void>()
        let pending = try #require(gate.tryBeginStartOperation())
        _ = gate.invalidate()

        #expect(gate.tryBeginStartOperation() == nil)

        gate.startOperationDidFinish()
        #expect(gate.tryBeginStartOperation() != nil)
        _ = gate.invalidate()
        gate.startOperationDidFinish()
        #expect(pending > 0)
    }

    @Test func directAreaStartFinishesItsOperationBeforeDeniedPreflightCanRetry() throws {
        let source = try recordingControllerSource()
        #expect(source.contains("let ownsStartOperation = startupGeneration == nil"))
        #expect(source.contains("if ownsStartOperation { startupGate.startOperationDidFinish() }"))

        let gate = CaptureStartGate<Void>()
        let denied = try #require(gate.tryBeginStartOperation())
        #expect(denied > 0)
        gate.startOperationDidFinish()
        _ = gate.invalidate()

        #expect(gate.tryBeginStartOperation() != nil)
    }

    @Test func gifCancellationWaitsForLateStartToStop() async throws {
        let gate = CaptureStartGate<String>()
        let startup = AsyncTestGate()
        let stopped = AsyncTestGate()
        let cancellationCompleted = AsyncTestGate()
        let generation = gate.beginStartOperation()

        let start = Task {
            await startup.wait()
            #expect(!gate.complete("late stream", for: generation))
            await stopped.resume()
            gate.startOperationDidFinish()
        }
        await startup.waitUntilStarted()

        let cancel = Task {
            _ = gate.invalidate()
            await gate.waitForStartOperations()
            await cancellationCompleted.resume()
        }
        await Task.yield()
        #expect(!(await cancellationCompleted.wasResumed()))

        await startup.resume()
        await start.value
        await cancel.value

        #expect(await stopped.wasResumed())
        let service = GIFRecordingService(maxFrames: 1)
        try service.beginCapture(fps: 10)
        await service.cancel()
        #expect(!service.acceptsFrames)
        #expect(!service.hasBufferedFrames)
    }

    @Test func gifStartRegistersCancellationOwnershipBeforeCapturePreparation() throws {
        let source = try gifRecordingServiceSource()
        let ownership = try #require(source.range(of: "captureStart.beginStartOperation()"))
        let preparation = try #require(source.range(of: "try beginCapture(fps: fps)"))

        #expect(ownership.lowerBound < preparation.lowerBound)
    }

    @Test func activeRecordingRejectsSecondaryOverlayWithoutConsumingItsOwner() async {
        let window = NSWindow()
        var restoreCount = 0
        let restoration = CaptureWindowRestoration(
            windows: [window],
            isVisible: { _ in true },
            restore: { _ in restoreCount += 1 }
        )
        let appState = AppState(captureWindowRestoration: restoration)
        appState.beginRecordingCaptureWindowOwnership(restoration.owner)
        appState.isRecording = true

        #expect(await appState.prepareForCaptureOverlay() == nil)
        appState.restoreCaptureWindows(owner: restoration.owner)

        #expect(restoreCount == 1)
    }

    @Test func recordingDuringOverlaySettleRestoresThisAttempt() async {
        let pause = AsyncTestGate()
        let window = NSWindow()
        var restoreCount = 0
        let restoration = CaptureWindowRestoration(
            windows: [window],
            isVisible: { _ in true },
            restore: { _ in restoreCount += 1 }
        )
        let appState = AppState(
            captureWindowRestorationFactory: { restoration },
            captureOverlaySettle: { await pause.wait() }
        )

        let attempt = Task { await appState.prepareForCaptureOverlay() }
        await pause.waitUntilStarted()
        appState.isRecording = true
        await pause.resume()
        let owner = await attempt.value

        #expect(owner == nil)
        #expect(appState.isRecording)
        #expect(restoreCount == 1)
    }

    @Test func fullScreenCaptureRestoresTransferredOwnerBeforeDelayCanReturn() throws {
        let source = try captureControllerSource()
        let restore = try #require(source.range(of: "defer { appState.restoreCaptureWindows(owner: owner) }"))
        let delay = try #require(source.range(of: "await CaptureDelay.wait"))

        #expect(restore.lowerBound < delay.lowerBound)
    }

    @Test func recordingOwnerSurvivesRejectionAndLegacyRestoreThenRestoresOnCancel() async throws {
        let window = NSWindow()
        var restoreCount = 0
        let restoration = CaptureWindowRestoration(
            windows: [window],
            isVisible: { _ in true },
            restore: { _ in restoreCount += 1 }
        )
        let appState = AppState(captureWindowRestoration: restoration)
        let controller = RecordingController(
            appState: appState,
            session: try activeSession()
        )

        appState.beginRecordingCaptureWindowOwnership(restoration.owner)
        controller.recordingDidStart(captureWindowOwner: restoration.owner)

        appState.restoreCaptureWindows()
        await controller.beginAreaRecording().value

        #expect(appState.isRecording)
        #expect(restoreCount == 0)

        await controller.stopRecording(save: false)

        #expect(!appState.isRecording)
        #expect(restoreCount == 1)
    }

    @Test func owningPreflightFailureRestoresCaptureWindows() async throws {
        let window = NSWindow()
        var restoreCount = 0
        let restoration = CaptureWindowRestoration(
            windows: [window],
            isVisible: { _ in true },
            restore: { _ in restoreCount += 1 }
        )
        let appState = AppState(captureWindowRestoration: restoration)
        let configuration = try fixtureConfiguration(requiredSpace: 1)
        let controller = RecordingController(appState: appState)
        let didContinue = try await controller.runPreflightForTesting(
            configuration: configuration,
            readiness: RecordingPreflightReadiness(
                permissionStatuses: [.screenRecording: .denied], availableSpaceBytes: 1
            ),
            captureWindowOwner: restoration.owner
        )

        #expect(!didContinue)
        #expect(!appState.isRecording)
        #expect(restoreCount == 1)
    }

    @Test func recoveryDiscoveryUsesInjectedTemporaryStoreAndMissingPostCaptureFileExplainsFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "WP04-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = try fixtureConfiguration(requiredSpace: 1)
        let snapshot = RecordingSessionSnapshot(sessionID: UUID(), configuration: configuration, createdAt: Date())
        let manifest = RecordingRecoveryManifest(
            session: snapshot, lifecycle: .recording,
            partialMedia: try RecordingRelativePath("partial.mp4"), updatedAt: Date()
        )
        try JSONEncoder().encode(manifest).write(to: directory.appending(path: "manifest.json"))
        #expect(RecordingRecoveryStore(directoryURL: directory).discover(at: Date()).count == 1)

        let post = RecordingPostCaptureModel(outputURL: directory.appending(path: "final.mp4"))
        #expect(post.editDisabledReason.contains("no longer available"))
    }

    private func fixtureConfiguration(requiredSpace: Int64) throws -> RecordingSessionConfiguration {
        try RecordingSessionConfiguration(
            source: .display(id: "display"), dimensions: RecordingDimensions(width: 1920, height: 1080),
            frameRate: RecordingFrameRate(framesPerSecond: 30), cursorMode: .visible,
            audio: RecordingAudioConfiguration(capturesSystemAudio: false), webcam: nil,
            countdown: RecordingCountdown(seconds: 0), events: RecordingEventConfiguration(),
            requiredSpaceEstimateBytes: requiredSpace
        )
    }

    private func activeSession() throws -> RecordingSessionController {
        let configuration = try fixtureConfiguration(requiredSpace: 1)
        let readiness = RecordingPreflightReadiness(
            permissionStatuses: [.screenRecording: .granted], availableSpaceBytes: 1
        )
        var session = RecordingSessionController()
        _ = try session.handle(.beginPreflight(configuration: configuration, sessionID: UUID(), at: Date()))
        _ = try session.handle(.resolvePreflight(readiness))
        return session
    }

    private func captureControllerSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "Aeroshot/Capture/CaptureController.swift"))
    }

    private func recordingControllerSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "Aeroshot/Recording/RecordingController.swift"))
    }

    private func gifRecordingServiceSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "Aeroshot/Recording/GIFRecordingService.swift"))
    }
}

private final class FakeRecordingService: RecordingServicing {
    var events: [String] = []
    func start(filter: SCContentFilter, configuration: SCStreamConfiguration, outputURL: URL,
               includeSystemAudio: Bool, includeMicrophone: Bool) async throws {}
    func stop() async throws -> URL { URL(fileURLWithPath: "/tmp/final.mp4") }
    func cancel() async { events.append("cancel") }
    func pause() -> Bool { events.append("pause"); return true }
    func resume() -> Bool { events.append("resume"); return true }
}

private final class TerminalRecordingService: RecordingServicing {
    let outputURL: URL
    let stopped = AsyncTestGate()
    var stopCalls = 0
    var cancelCalls = 0

    init(outputURL: URL) { self.outputURL = outputURL }

    func start(filter: SCContentFilter, configuration: SCStreamConfiguration, outputURL: URL,
               includeSystemAudio: Bool, includeMicrophone: Bool) async throws {}
    func stop() async throws -> URL {
        stopCalls += 1
        await stopped.wait()
        return outputURL
    }
    func cancel() async { cancelCalls += 1 }
    func pause() -> Bool { false }
    func resume() -> Bool { false }
    func waitUntilStopping() async { await stopped.waitUntilStarted() }
    func finishStop() async { await stopped.resume() }
}

private actor AsyncTestGate {
    private var hasStarted = false
    private var wasReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        hasStarted = true
        let waiters = startWaiters
        startWaiters = []
        waiters.forEach { $0.resume() }
        guard !wasReleased else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resume() {
        wasReleased = true
        let waiters = releaseWaiters
        releaseWaiters = []
        waiters.forEach { $0.resume() }
    }

    func wasResumed() -> Bool { wasReleased }
}

private actor StartCounter {
    private(set) var value = 0

    func record() { value += 1 }
}
