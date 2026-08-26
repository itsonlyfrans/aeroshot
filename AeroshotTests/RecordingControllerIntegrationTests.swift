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

    @Test func mp4PreflightUsesTheLowerRecoveryAndPublicationCapacity() throws {
        let source = try recordingControllerSource()
        let recoveryRoot = try #require(source.range(of: "try FileManager.default.createDirectory(at: Self.recoveryDirectory"))
        let capacity = try #require(source.range(of: "Self.availableSpace(in: Self.recoveryDirectory)"))
        let publicationCapacity = try #require(source.range(of: "Self.availableSpace(forFileAt: url)", range: capacity.upperBound..<source.endIndex))
        let directoryHelper = try #require(source.range(of: "private static func availableSpace(in directory: URL)"))
        let fileHelper = try #require(source.range(of: "private static func availableSpace(forFileAt url: URL)", range: directoryHelper.upperBound..<source.endIndex))
        let directoryQuery = source[directoryHelper.lowerBound..<fileHelper.lowerBound]

        #expect(recoveryRoot.lowerBound < capacity.lowerBound)
        #expect(capacity.lowerBound < publicationCapacity.lowerBound)
        #expect(directoryQuery.contains("directory.resourceValues"))
        #expect(!directoryQuery.contains("deletingLastPathComponent"))
    }

    @Test func failedWorkspacePublicationKeepsRecoveryArtifacts() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "RecordingPublication-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appending(path: "workspace", directoryHint: .isDirectory)
        let destination = root.appending(path: "destination", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let workspaceMedia = workspace.appending(path: "recording.mp4")
        let workspaceSidecar = RecordingEffectEventRecorder.sidecarURL(for: workspaceMedia)
        let manifest = workspace.appending(path: "manifest.json")
        let destinationMedia = destination.appending(path: "recording.mp4")
        let destinationSidecar = RecordingEffectEventRecorder.sidecarURL(for: destinationMedia)
        let sentinel = root.appending(path: "sentinel")
        try Data("media".utf8).write(to: workspaceMedia)
        try Data("sidecar".utf8).write(to: workspaceSidecar)
        try Data("manifest".utf8).write(to: manifest)
        try Data("existing".utf8).write(to: destinationMedia)
        try Data("keep".utf8).write(to: sentinel)

        #expect(throws: (any Error).self) {
            try RecordingController.publishWorkspaceMedia(workspaceMedia, to: destinationMedia)
        }

        #expect(FileManager.default.fileExists(atPath: workspaceMedia.path))
        #expect(FileManager.default.fileExists(atPath: workspaceSidecar.path))
        #expect(FileManager.default.fileExists(atPath: manifest.path))
        #expect(!FileManager.default.fileExists(atPath: destinationSidecar.path))
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test func recoveryAlertExplainsActionsAndPrioritizesAvailableMedia() throws {
        let source = try appDelegateSource()
        let recovery = try #require(source.range(of: "private func showRecordingRecoveryDecision"))
        let end = try #require(source.range(of: "private var lastEffectiveHotkeys", range: recovery.upperBound..<source.endIndex))
        let body = source[recovery.lowerBound..<end.lowerBound]
        let activation = try #require(body.range(of: "NSApp.activate(ignoringOtherApps: true)"))
        let modal = try #require(body.range(of: "alert.runModal()"))

        #expect(activation.lowerBound < modal.lowerBound)
        #expect(body.contains("artifacts.first(where: { $0.mediaURL != nil })"))
        #expect(body.contains("Aeroshot found an unfinished recording."))
        #expect(body.contains("Open Partial Recording"))
        #expect(body.contains("Delete Partial Recording"))
        #expect(body.contains("Delete All \\(count) Recovery Items"))
        #expect(body.contains("Aeroshot creates these records while recording."))
        #expect(body.contains("Clearing removes only these records. It does not delete saved recordings."))
        #expect(body.contains("Clear \\(count) Recovery Records"))
        #expect(body.contains("try store.discard(artifacts)"))
        #expect(body.contains("Aeroshot could not delete all recovery data."))

        let staleStart = try #require(body.range(of: "let count = artifacts.count"))
        let staleBody = body[staleStart.lowerBound...]
        let keep = try #require(staleBody.range(of: "alert.addButton(withTitle: \"Keep for Next Launch\")"))
        let clear = try #require(staleBody.range(of: "let clearButton = alert.addButton"))
        #expect(keep.lowerBound < clear.lowerBound)
        #expect(staleBody.contains("if alert.runModal() == .alertSecondButtonReturn"))
        #expect(staleBody.contains("clearButton.hasDestructiveAction = true"))
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

    @Test func unexpectedStreamFailureNotifiesOnlyOnce() {
        let service = ScreenRecordingService()
        let counter = LockedCounter()
        service.unexpectedStopHandler = { counter.increment() }
        service.installActiveCaptureForUnexpectedStopTesting()

        service.simulateUnexpectedStopForTesting()
        service.simulateUnexpectedStopForTesting()

        #expect(counter.value == 1)
    }

    @Test func gifUnexpectedStreamFailureNotifiesOnlyOnce() throws {
        let service = GIFRecordingService(maxFrames: 1)
        let counter = LockedCounter()
        service.unexpectedStopHandler = { counter.increment() }
        try service.beginCapture(fps: 10)

        service.simulateUnexpectedStopForTesting()
        service.simulateUnexpectedStopForTesting()

        #expect(counter.value == 1)
        #expect(!service.acceptsFrames)
    }

    @Test func videoAndGIFStreamFailuresLeaveRecordingState() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "StreamFailure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let videoState = AppState()
        let videoController = RecordingController(appState: videoState, session: try activeSession())
        let videoService = ScreenRecordingService()
        videoService.installActiveCaptureForUnexpectedStopTesting()
        videoController.installRecordingForTesting(
            recorder: videoService,
            outputURL: directory.appending(path: "partial.mp4")
        )
        videoService.simulateUnexpectedStopForTesting()
        await waitForRecordingToStop(videoState)
        #expect(!(await videoController.stopRecording(save: true)))
        #expect(!videoState.isRecording)

        let gifState = AppState()
        let gifController = RecordingController(appState: gifState, session: try activeSession())
        let gifService = GIFRecordingService(maxFrames: 1)
        try gifService.beginCapture(fps: 10)
        gifController.installGIFRecordingForTesting(
            service: gifService,
            outputURL: directory.appending(path: "partial.gif")
        )
        gifService.simulateUnexpectedStopForTesting()
        await waitForRecordingToStop(gifState)
        #expect(!(await gifController.stopRecording(save: true)))
        #expect(!gifState.isRecording)
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
        #expect(await first.value)
        #expect(await second.value)

        await controller.stopRecording(save: false)

        #expect(service.stopCalls == 1)
        #expect(service.cancelCalls == 0)
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test func failedFinalizationReturnsFalseAndLeavesRecordingState() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RecordingFailure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appending(path: "capture.mp4")
        try Data("partial".utf8).write(to: output)
        let service = FailingRecordingService()
        let appState = AppState()
        let controller = RecordingController(appState: appState, session: try activeSession())
        controller.installRecordingForTesting(recorder: service, outputURL: output)

        #expect(!(await controller.stopRecording(save: true)))
        #expect(!appState.isRecording)
        #expect(service.stopCalls == 1)
        #expect(service.cancelCalls == 1)
        #expect(!FileManager.default.fileExists(atPath: output.path))
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

    @Test func delayedCaptureCanCancelEscapeFromAnotherApp() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Aeroshot/Capture/CaptureDelay.swift"))

        #expect(source.contains("NSEvent.addLocalMonitorForEvents(matching: .keyDown)"))
        #expect(source.contains("NSEvent.addGlobalMonitorForEvents(matching: .keyDown)"))
        #expect(source.contains("NSEvent.removeMonitor(globalKeyMonitor)"))
        #expect(source.contains("withExtendedLifetime(controller)"))
    }

    @Test func recordingBecomesActiveBeforeCountdownStarts() throws {
        let source = try recordingControllerSource()
        let preflight = try #require(source.range(of: "guard let effect = try resolvePreflight"))
        let active = try #require(source.range(of: "appState.isRecording = true", range: preflight.upperBound..<source.endIndex))
        let countdown = try #require(source.range(of: "if effect == .scheduleCountdownTick", range: active.upperBound..<source.endIndex))

        #expect(preflight.lowerBound < active.lowerBound)
        #expect(active.lowerBound < countdown.lowerBound)
    }

    @Test func recordingHotkeyCannotStealAnActiveCaptureOverlay() throws {
        let source = try recordingControllerSource()
        let begin = try #require(source.range(of: "private func beginStartup"))
        let end = try #require(source.range(of: "private func ownsStartup", range: begin.upperBound..<source.endIndex))
        let body = source[begin.lowerBound..<end.lowerBound]
        let normalized = body.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")

        #expect(normalized.contains(
            "guard !isRecording, !isFinalizing, captureWindowOwner != nil || "
                + "(!appState.captureController.isPresentingOverlay && !appState.allInOneController.isPresenting), "
                + "let generation = startupGate.tryBeginStartOperation() else { return nil }"
        ))
    }

    @Test func recordingFinalizationDoesNotAwaitPostCaptureImports() throws {
        let source = try recordingControllerSource()
        let start = try #require(source.range(of: "if let savedURL {"))
        let end = try #require(source.range(of: "private func startElapsedTimer", range: start.upperBound..<source.endIndex))
        let finalization = source[start.lowerBound..<end.lowerBound]

        #expect(finalization.contains("Task {\n                    guard await history.add(recordingFrom:"))
        #expect(finalization.contains("Task { await appState.uploadIfNeeded(fileURL: savedURL) }"))
        #expect(!finalization.contains("_ = await appState.history.add(recordingFrom:"))
    }

    @Test func recordingFinalizationClearsSavedURLAfterFinalizationFailure() throws {
        let source = try recordingControllerSource()
        let start = try #require(source.range(of: "var savedURL: URL?"))
        let end = try #require(source.range(of: "private func startElapsedTimer", range: start.upperBound..<source.endIndex))
        let finalization = source[start.lowerBound..<end.lowerBound]
        let failure = try #require(finalization.range(of: "} catch {"))
        let clear = try #require(finalization.range(of: "savedURL = nil", range: failure.upperBound..<finalization.endIndex))
        let success = try #require(finalization.range(of: "if let savedURL {", range: clear.upperBound..<finalization.endIndex))

        #expect(failure.lowerBound < clear.lowerBound)
        #expect(clear.lowerBound < success.lowerBound)
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

    @Test func recoveryStoreDiscoversPartialGIFMedia() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GIFRecovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = try fixtureConfiguration(requiredSpace: 1)
        let snapshot = RecordingSessionSnapshot(sessionID: UUID(), configuration: configuration, createdAt: Date())
        let sessionDirectory = root.appending(path: snapshot.sessionID.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let mediaURL = sessionDirectory.appending(path: "partial.gif")
        try Data("gif".utf8).write(to: mediaURL)
        let manifest = RecordingRecoveryManifest(
            session: snapshot,
            lifecycle: .stopping,
            partialMedia: try RecordingRelativePath(mediaURL.lastPathComponent),
            updatedAt: Date()
        )
        try JSONEncoder().encode(manifest).write(to: sessionDirectory.appending(path: "manifest.json"))

        let artifact = try #require(RecordingRecoveryStore(directoryURL: root).discoverArtifacts(at: Date()).first)
        #expect(artifact.mediaURL?.resolvingSymlinksInPath() == mediaURL.resolvingSymlinksInPath())
    }

    @Test func mp4WriterConfiguresRecoveryFragmentsBeforeCapture() throws {
        let source = try screenRecordingServiceSource()
        let writer = try #require(source.range(of: "let writer = try AVAssetWriter"))
        let fragments = try #require(source.range(of: "writer.movieFragmentInterval = CMTime(seconds: 10"))
        #expect(writer.lowerBound < fragments.lowerBound)
        #expect(source.contains("writer.initialMovieFragmentInterval = CMTime(seconds: 1"))
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

    private func waitForRecordingToStop(_ appState: AppState) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while appState.isRecording, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
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

    private func appDelegateSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "Aeroshot/App/AppDelegate.swift"))
    }

    private func gifRecordingServiceSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "Aeroshot/Recording/GIFRecordingService.swift"))
    }

    private func screenRecordingServiceSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "Aeroshot/Recording/ScreenRecordingService.swift"))
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

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
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

private final class FailingRecordingService: RecordingServicing {
    enum Failure: Error { case finalization }

    var stopCalls = 0
    var cancelCalls = 0

    func start(filter: SCContentFilter, configuration: SCStreamConfiguration, outputURL: URL,
               includeSystemAudio: Bool, includeMicrophone: Bool) async throws {}
    func stop() async throws -> URL {
        stopCalls += 1
        throw Failure.finalization
    }
    func cancel() async { cancelCalls += 1 }
    func pause() -> Bool { false }
    func resume() -> Bool { false }
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
