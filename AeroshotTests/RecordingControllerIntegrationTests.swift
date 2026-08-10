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

    @Test func gifDiscardStopsFrameAcceptanceAndClearsItsSpool() async throws {
        let service = GIFRecordingService(maxFrames: 1)
        _ = try service.beginCapture(fps: 10)
        #expect(service.acceptsFrames)
        #expect(service.hasBufferedFrames)

        await service.cancel()

        #expect(!service.acceptsFrames)
        #expect(!service.hasBufferedFrames)
    }

    @Test func cancellationRejectsLateCaptureStartBeforeItCanRetainTheStream() {
        let gate = CaptureStartGate<String>()
        let generation = gate.begin()

        #expect(gate.invalidate() == nil)
        #expect(!gate.complete("late stream", for: generation))
        #expect(gate.invalidate() == nil)
    }

    @Test func gifCancellationWaitsForLateStartToStop() async throws {
        let gate = CaptureStartGate<String>()
        let startup = AsyncTestGate()
        let stopped = AsyncTestGate()
        let generation = gate.begin()
        gate.startOperationDidBegin()

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
        }
        await Task.yield()
        let stoppedBeforeStartupCompleted = await stopped.wasResumed()
        #expect(!stoppedBeforeStartupCompleted)

        await startup.resume()
        await start.value
        await cancel.value

        #expect(await stopped.wasResumed())
        let service = GIFRecordingService(maxFrames: 1)
        _ = try service.beginCapture(fps: 10)
        await service.cancel()
        #expect(!service.acceptsFrames)
        #expect(!service.hasBufferedFrames)
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
