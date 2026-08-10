import Foundation
import Testing
@testable import Aeroshot

struct RecordingSessionTests {
    private let sessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let date = Date(timeIntervalSince1970: 1_784_000_000)

    @Test func completeHappyPathRequiresDurableFinalization() throws {
        var controller = RecordingSessionController()
        #expect(try controller.handle(.beginPreflight(configuration: configuration(), sessionID: sessionID, at: date)) == .runPreflight)
        #expect(try controller.handle(.resolvePreflight(readiness())) == .beginCapture)
        #expect(controller.state.name == "recording")
        #expect(try controller.handle(.pause) == .pauseCapture)
        #expect(try controller.handle(.resume) == .resumeCapture)
        #expect(try controller.handle(.stop) == .finalizeDurably)
        let output = try RecordingCompletedOutput(
            relativePath: RecordingRelativePath("final/session.mov"),
            byteCount: 42,
            durationSeconds: 6,
            finalizedAt: date
        )
        #expect(output.durationSeconds == 6)
        #expect(try controller.handle(.finalize(output: output, isDurable: true)) == .none)
        #expect(controller.state == .completed(output))
    }

    @Test func incompleteFinalizationCanNeverBecomeCompleted() throws {
        var controller = try recordingController()
        _ = try controller.handle(.stop)
        let output = try RecordingCompletedOutput(
            relativePath: RecordingRelativePath("final/session.mov"),
            byteCount: 42,
            finalizedAt: date
        )
        #expect(try controller.handle(.finalize(output: output, isDurable: false)) == .preserveRecoverableArtifacts)
        #expect(controller.state == .failed(.finalizationNotDurable))
    }

    @Test func countdownVisitsEveryTickBeforeCapture() throws {
        var controller = RecordingSessionController()
        _ = try controller.handle(.beginPreflight(
            configuration: configuration(countdown: 2), sessionID: sessionID, at: date
        ))
        #expect(try controller.handle(.resolvePreflight(readiness())) == .scheduleCountdownTick)
        #expect(controller.state.name == "countdown")
        #expect(try controller.handle(.countdownTick) == .scheduleCountdownTick)
        #expect(try controller.handle(.countdownTick) == .beginCapture)
        #expect(controller.state.name == "recording")
    }

    @Test(arguments: [
        (RecordingPermission.screenRecording, RecordingPermissionStatus.denied),
        (.screenRecording, .restricted),
        (.screenRecording, .notDetermined),
        (.microphone, .denied),
        (.camera, .denied),
    ])
    func permissionFailureIsDeterministic(permission: RecordingPermission, status: RecordingPermissionStatus) throws {
        var controller = RecordingSessionController()
        _ = try controller.handle(.beginPreflight(
            configuration: configuration(microphone: true, webcam: true), sessionID: sessionID, at: date
        ))
        var statuses = grantedPermissions
        statuses[permission] = status
        let effect = try controller.handle(.resolvePreflight(RecordingPreflightReadiness(
            permissionStatuses: statuses, availableSpaceBytes: 2_000
        )))
        #expect(effect == .discardTransientArtifacts)
        #expect(controller.state == .failed(.permissionUnavailable(permission: permission, status: status)))
    }

    @Test func unavailableDeviceAndLowSpaceHaveTypedFailures() throws {
        var deviceController = RecordingSessionController()
        _ = try deviceController.handle(.beginPreflight(
            configuration: configuration(microphone: true), sessionID: sessionID, at: date
        ))
        _ = try deviceController.handle(.resolvePreflight(RecordingPreflightReadiness(
            permissionStatuses: grantedPermissions,
            unavailableDeviceIDs: ["mic-1"],
            availableSpaceBytes: 2_000
        )))
        #expect(deviceController.state == .failed(.deviceUnavailable(id: "mic-1")))

        var spaceController = RecordingSessionController()
        _ = try spaceController.handle(.beginPreflight(
            configuration: configuration(), sessionID: sessionID, at: date
        ))
        _ = try spaceController.handle(.resolvePreflight(RecordingPreflightReadiness(
            permissionStatuses: grantedPermissions, availableSpaceBytes: 999
        )))
        #expect(spaceController.state == .failed(.insufficientSpace(requiredBytes: 1_000, availableBytes: 999)))
    }

    @Test func interruptionFromRecordingPausedAndStoppingIsRecoverable() throws {
        for stage in ["recording", "paused", "stopping"] {
            var controller = try recordingController()
            if stage == "paused" { _ = try controller.handle(.pause) }
            if stage == "stopping" { _ = try controller.handle(.stop) }
            let manifest = try recoveryManifest(lifecycle: stage == "stopping" ? .stopping : stage == "paused" ? .paused : .recording)
            #expect(try controller.handle(.interrupt(manifest)) == .preserveRecoverableArtifacts)
            #expect(controller.state == .recoverableInterruption(manifest))
            #expect(try controller.handle(.recover) == .loadRecoverableArtifacts)
            #expect(controller.state.name == "paused")
        }
    }

    @Test func mismatchedRecoveryCannotReplaceActiveSession() throws {
        var controller = try recordingController()
        let other = try recoveryManifest(sessionID: UUID())
        #expect(throws: RecordingSessionTransitionError.recoverySessionMismatch) {
            try controller.handle(.interrupt(other))
        }
        #expect(controller.state.name == "recording")
    }

    @Test func cancellationIsIdempotentAndCleanupIsEmittedOnce() throws {
        var idle = RecordingSessionController()
        #expect(try idle.handle(.cancel) == .none)
        #expect(try idle.handle(.cancel) == .none)

        var active = try recordingController()
        #expect(try active.handle(.cancel) == .discardTransientArtifacts)
        #expect(active.state == .cancelled)
        #expect(try active.handle(.cancel) == .none)

        for stage in ["preflight", "countdown", "paused", "stopping", "recovery"] {
            var controller = try controller(at: stage)
            #expect(try controller.handle(.cancel) == .discardTransientArtifacts)
            #expect(try controller.handle(.cancel) == .none)
        }
    }

    @Test func explicitFailuresAreAcceptedFromEveryActiveCaptureStage() throws {
        for stage in ["preflight", "countdown", "recording", "paused", "stopping"] {
            var controller = try controller(at: stage)
            let failure = RecordingSessionFailure.captureFailed(code: "fixture")
            #expect(try controller.handle(.fail(failure)) == .preserveRecoverableArtifacts)
            #expect(controller.state == .failed(failure))
        }
    }

    @Test func invalidTransitionsAreRejectedWithoutMutation() throws {
        var controller = RecordingSessionController()
        #expect(throws: RecordingSessionTransitionError.invalidTransition(event: "pause", state: "idle")) {
            try controller.handle(.pause)
        }
        #expect(controller.state == .idle)
    }

    @Test func configurationValueTypesRejectInvalidInputAndDecode() throws {
        #expect(throws: RecordingSessionModelError.invalidDimensions) { try RecordingDimensions(width: 0, height: 1) }
        #expect(throws: RecordingSessionModelError.invalidFrameRate) { try RecordingFrameRate(framesPerSecond: 0) }
        #expect(throws: RecordingSessionModelError.invalidCountdown) { try RecordingCountdown(seconds: 11) }
        #expect(throws: RecordingSessionModelError.invalidDeviceIdentifier) { try RecordingWebcamConfiguration(deviceID: "") }
        #expect(throws: RecordingSessionModelError.invalidSpaceEstimate) {
            try configuration(requiredSpace: 0)
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RecordingDimensions.self, from: Data(#"{"width":0,"height":10}"#.utf8))
        }
    }

    @Test func recoveryManifestRoundTripsAndRejectsUnsafeReferences() throws {
        let manifest = try recoveryManifest()
        let encoded = try JSONEncoder().encode(manifest)
        #expect(try JSONDecoder().decode(RecordingRecoveryManifest.self, from: encoded) == manifest)
        for path in ["/tmp/file", "../file", "partial//file", "partial\\file", ""] {
            #expect(throws: (any Error).self) { try RecordingRelativePath(path) }
        }
    }

    @Test func recoveryDiscoveryFiltersCorruptAndExpiredThenSortsDeterministically() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RecordingRecovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let older = try recoveryManifest(updatedAt: date)
        let newer = try recoveryManifest(sessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, updatedAt: date.addingTimeInterval(10))
        let expired = try recoveryManifest(
            sessionID: UUID(), updatedAt: date,
            retention: RecordingPrivacyRetentionPolicy(
                interruptedSession: .retainUntil(date),
                deleteOnExplicitCancel: true,
                capturedContentExcludedFromDiagnostics: true,
                eventMetadataExcludedFromDiagnostics: true
            )
        )
        try JSONEncoder().encode(older).write(to: directory.appending(path: "older.json"))
        try JSONEncoder().encode(newer).write(to: directory.appending(path: "newer.json"))
        try JSONEncoder().encode(expired).write(to: directory.appending(path: "expired.json"))
        try Data("bad".utf8).write(to: directory.appending(path: "corrupt.json"))
        try Data("ignored".utf8).write(to: directory.appending(path: "note.txt"))

        let found = RecordingRecoveryStore(directoryURL: directory).discover(at: date)
        #expect(found.map(\.session.sessionID) == [newer.session.sessionID, older.session.sessionID])
    }

    @Test func effectMatrixHasOneDecisionPerEffectAndDocumentsFallbacks() throws {
        let config = try configuration(microphone: true, webcam: true, keystrokes: true)
        let metadata = RecordingEffectCapturePolicy.matrix(
            configuration: config,
            capabilities: .init(cursorMetadata: true, clickMetadata: true, webcamSeparateStream: true),
            secureInputActive: false
        )
        #expect(metadata.map(\.kind) == RecordingEffectKind.allCases)
        #expect(metadata.allSatisfy { $0.isExcludedFromDiagnostics })
        #expect(metadata.allSatisfy { $0.storage == .editableMetadata })
        #expect(metadata.allSatisfy { $0.isInspectable })
        #expect(metadata.allSatisfy { $0.isDeletable })

        let fallback = RecordingEffectCapturePolicy.matrix(
            configuration: config,
            capabilities: .init(cursorMetadata: false, clickMetadata: false, webcamSeparateStream: false),
            secureInputActive: false
        )
        #expect(fallback.first { $0.kind == .cursor }?.storage == .bakedIntoMedia)
        #expect(fallback.first { $0.kind == .click }?.storage == .bakedIntoMedia)
        #expect(fallback.first { $0.kind == .webcam }?.storage == .bakedIntoMedia)
        #expect(fallback.first { $0.kind == .keystroke }?.storage == .editableMetadata)
    }

    @Test func keystrokesRequireOptInVisibleIndicatorAndExcludeSecureInput() throws {
        let capabilities = RecordingEffectCaptureCapabilities(cursorMetadata: true, clickMetadata: true, webcamSeparateStream: true)
        for (optIn, indicator, secureInput) in [
            (false, true, false), (true, false, false), (true, true, true),
        ] {
            let config = try configuration(events: RecordingEventConfiguration(
                capturesKeystrokes: optIn,
                showsKeystrokeCaptureIndicator: indicator
            ))
            let decision = RecordingEffectCapturePolicy.matrix(
                configuration: config, capabilities: capabilities, secureInputActive: secureInput
            ).first { $0.kind == .keystroke }
            #expect(decision?.storage == .disabled)
            #expect(decision?.excludesSecureInput == true)
            #expect(decision?.requiresVisibleIndicator == true)
        }
    }

    private var grantedPermissions: [RecordingPermission: RecordingPermissionStatus] {
        [.screenRecording: .granted, .microphone: .granted, .camera: .granted]
    }

    private func readiness() -> RecordingPreflightReadiness {
        RecordingPreflightReadiness(permissionStatuses: grantedPermissions, availableSpaceBytes: 2_000)
    }

    private func configuration(
        countdown: Int = 0,
        microphone: Bool = false,
        webcam: Bool = false,
        keystrokes: Bool = false,
        requiredSpace: Int64 = 1_000,
        events: RecordingEventConfiguration? = nil
    ) throws -> RecordingSessionConfiguration {
        try RecordingSessionConfiguration(
            source: .display(id: "display-1"),
            dimensions: RecordingDimensions(width: 1_920, height: 1_080),
            frameRate: RecordingFrameRate(framesPerSecond: 60),
            cursorMode: .visibleWithClickEffects,
            audio: RecordingAudioConfiguration(
                capturesSystemAudio: true,
                microphoneDeviceID: microphone ? "mic-1" : nil
            ),
            webcam: webcam ? RecordingWebcamConfiguration(deviceID: "camera-1") : nil,
            countdown: RecordingCountdown(seconds: countdown),
            events: events ?? RecordingEventConfiguration(
                capturesClicks: true,
                capturesKeystrokes: keystrokes,
                showsKeystrokeCaptureIndicator: keystrokes
            ),
            requiredSpaceEstimateBytes: requiredSpace
        )
    }

    private func recordingController() throws -> RecordingSessionController {
        var controller = RecordingSessionController()
        _ = try controller.handle(.beginPreflight(configuration: configuration(), sessionID: sessionID, at: date))
        _ = try controller.handle(.resolvePreflight(readiness()))
        return controller
    }

    private func controller(at stage: String) throws -> RecordingSessionController {
        if stage == "preflight" {
            var result = RecordingSessionController()
            _ = try result.handle(.beginPreflight(configuration: configuration(), sessionID: sessionID, at: date))
            return result
        }
        if stage == "countdown" {
            var result = RecordingSessionController()
            _ = try result.handle(.beginPreflight(configuration: configuration(countdown: 2), sessionID: sessionID, at: date))
            _ = try result.handle(.resolvePreflight(readiness()))
            return result
        }
        var result = try recordingController()
        if stage == "paused" { _ = try result.handle(.pause) }
        if stage == "stopping" { _ = try result.handle(.stop) }
        if stage == "recovery" { _ = try result.handle(.interrupt(recoveryManifest())) }
        return result
    }

    private func recoveryManifest(
        sessionID: UUID? = nil,
        lifecycle: RecordingRecoveryLifecycle = .recording,
        updatedAt: Date? = nil,
        retention: RecordingPrivacyRetentionPolicy = .privateByDefault
    ) throws -> RecordingRecoveryManifest {
        RecordingRecoveryManifest(
            session: RecordingSessionSnapshot(
                sessionID: sessionID ?? self.sessionID,
                configuration: try configuration(),
                createdAt: date
            ),
            lifecycle: lifecycle,
            partialMedia: try RecordingRelativePath("partial/session.mov"),
            eventMetadata: [try RecordingRelativePath("events/cursor.json")],
            updatedAt: updatedAt ?? date,
            retention: retention
        )
    }
}
