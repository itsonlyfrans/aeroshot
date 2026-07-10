import Foundation

/// Pure recording-session reducer. It owns no ScreenCaptureKit, device, timer,
/// or filesystem objects; callers perform the returned effect and feed the
/// deterministic result back as another event.
nonisolated struct RecordingSessionController: Sendable {
    private(set) var state: RecordingSessionState = .idle

    @discardableResult
    mutating func handle(_ event: RecordingSessionEvent) throws -> RecordingSessionEffect {
        switch (state, event) {
        case let (.idle, .beginPreflight(configuration, sessionID, date)):
            state = .preflighting(RecordingSessionSnapshot(
                sessionID: sessionID,
                configuration: configuration,
                createdAt: date
            ))
            return .runPreflight

        case let (.preflighting(snapshot), .resolvePreflight(readiness)):
            if let failure = preflightFailure(configuration: snapshot.configuration, readiness: readiness) {
                state = .failed(failure)
                return .discardTransientArtifacts
            }
            let seconds = snapshot.configuration.countdown.seconds
            if seconds > 0 {
                state = .countdown(snapshot, remainingSeconds: seconds)
                return .scheduleCountdownTick
            }
            state = .recording(snapshot)
            return .beginCapture

        case let (.countdown(snapshot, remaining), .countdownTick):
            if remaining > 1 {
                state = .countdown(snapshot, remainingSeconds: remaining - 1)
                return .scheduleCountdownTick
            }
            state = .recording(snapshot)
            return .beginCapture

        case let (.recording(snapshot), .pause):
            state = .paused(snapshot)
            return .pauseCapture

        case let (.paused(snapshot), .resume):
            state = .recording(snapshot)
            return .resumeCapture

        case let (.recording(snapshot), .stop), let (.paused(snapshot), .stop):
            state = .stopping(snapshot)
            return .finalizeDurably

        case let (.stopping, .finalize(output, isDurable)):
            guard isDurable else {
                state = .failed(.finalizationNotDurable)
                return .preserveRecoverableArtifacts
            }
            state = .completed(output)
            return .none

        case let (.recording(snapshot), .interrupt(manifest)),
             let (.paused(snapshot), .interrupt(manifest)),
             let (.stopping(snapshot), .interrupt(manifest)):
            guard manifest.session.sessionID == snapshot.sessionID else {
                throw RecordingSessionTransitionError.recoverySessionMismatch
            }
            state = .recoverableInterruption(manifest)
            return .preserveRecoverableArtifacts

        case let (.recoverableInterruption(manifest), .recover):
            state = .paused(manifest.session)
            return .loadRecoverableArtifacts

        case (.cancelled, .cancel):
            // Cancellation and its cleanup effect are intentionally idempotent.
            return .none

        case (.idle, .cancel):
            state = .cancelled
            return .none

        case (.preflighting, .cancel), (.countdown, .cancel), (.recording, .cancel),
             (.paused, .cancel), (.stopping, .cancel), (.recoverableInterruption, .cancel):
            state = .cancelled
            return .discardTransientArtifacts

        case (.preflighting, .fail(let failure)), (.countdown, .fail(let failure)),
             (.recording, .fail(let failure)), (.paused, .fail(let failure)),
             (.stopping, .fail(let failure)):
            state = .failed(failure)
            return .preserveRecoverableArtifacts

        default:
            throw RecordingSessionTransitionError.invalidTransition(
                event: Self.name(of: event),
                state: state.name
            )
        }
    }

    private func preflightFailure(
        configuration: RecordingSessionConfiguration,
        readiness: RecordingPreflightReadiness
    ) -> RecordingSessionFailure? {
        var requiredPermissions: [RecordingPermission] = [.screenRecording]
        if configuration.audio.microphoneDeviceID != nil { requiredPermissions.append(.microphone) }
        if configuration.webcam != nil { requiredPermissions.append(.camera) }

        for permission in requiredPermissions {
            let status = readiness.permissionStatuses[permission] ?? .notDetermined
            if status != .granted {
                return .permissionUnavailable(permission: permission, status: status)
            }
        }

        let deviceIDs = [configuration.audio.microphoneDeviceID, configuration.webcam?.deviceID].compactMap { $0 }
        if let unavailable = deviceIDs.first(where: readiness.unavailableDeviceIDs.contains) {
            return .deviceUnavailable(id: unavailable)
        }

        if readiness.availableSpaceBytes < configuration.requiredSpaceEstimateBytes {
            return .insufficientSpace(
                requiredBytes: configuration.requiredSpaceEstimateBytes,
                availableBytes: readiness.availableSpaceBytes
            )
        }
        return nil
    }

    private static func name(of event: RecordingSessionEvent) -> String {
        switch event {
        case .beginPreflight: "beginPreflight"
        case .resolvePreflight: "resolvePreflight"
        case .countdownTick: "countdownTick"
        case .pause: "pause"
        case .resume: "resume"
        case .stop: "stop"
        case .finalize: "finalize"
        case .interrupt: "interrupt"
        case .recover: "recover"
        case .cancel: "cancel"
        case .fail: "fail"
        }
    }
}
