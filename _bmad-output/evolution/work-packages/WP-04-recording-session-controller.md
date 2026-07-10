# WP-04 controller — Recording session state and recovery

## Mission

Implement the recording-session domain kernel required by Phase 3: explicit state transitions, preflight configuration, privacy-aware event policy, disk/interruption recovery metadata, and deterministic failure semantics.

## Allowed files

- `Aeroshot/Recording/Session/**`
- `AeroshotTests/RecordingSessionTests.swift`
- `_bmad-output/evolution/specs/WP-04-effect-capture-matrix.md`
- `_bmad-output/evolution/test-reports/WP-04-recording-session.md`

Do not edit current recording controller/service, themes, project schema, editor, history, or project.pbxproj.

## Required implementation

- State machine covering idle, preflighting, countdown, recording, paused, stopping, completed, cancelled, failed, and recoverable interruption.
- Typed preflight source, dimensions/frame rate, cursor, system/microphone audio, webcam, countdown, permission/device readiness, and required-space estimate.
- Validated transition errors; idempotent cancellation/cleanup policy; completed output only after durable finalization.
- Codable recoverable-session manifest using safe relative references and privacy retention policy.
- Effect-capture matrix for cursor, click, keystroke, and webcam metadata versus baked fallback. Keystrokes opt-in, visibly active, secure-input excluded, inspectable/deletable, diagnostics-excluded.
- Deterministic tests for every transition branch, low space, denial, interruption, cancellation, and recovery discovery.

## Truth and gate

This package is a real domain/recovery kernel, not UI or live ScreenCaptureKit integration. Gate: state/recovery tests pass and no transition can present incomplete media as completed.
