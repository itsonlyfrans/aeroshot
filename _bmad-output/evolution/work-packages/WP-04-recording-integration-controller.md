# WP-04 controller — Live recording integration

## Mission

Connect the tested recording-session reducer and timestamp-correcting service to the real recording controller/HUD while preserving current capture defaults and macOS 14.6 behavior.

## Allowed files

- `Aeroshot/Recording/RecordingController.swift`
- `Aeroshot/Recording/RecordingPreflightView.swift`
- `Aeroshot/Recording/RecordingPostCapture.swift`
- `AeroshotTests/RecordingControllerIntegrationTests.swift`
- `_bmad-output/evolution/test-reports/WP-04-recording-integration.md`

Do not edit ScreenRecordingService, session-kernel files, project schema, editor, themes, GIF service, history, or project.pbxproj.

## Required implementation

- Drive controller and HUD from explicit session state rather than independent booleans.
- Add real Pause/Resume controls calling the timestamp-correcting service, plus Stop and explicit Cancel.
- Add preflight model/surface for current source, resolution/rate, cursor, microphone/system audio, webcam, countdown, permission readiness, and low-space blocking; existing quick recording may use approved defaults without mandatory configuration.
- Persist/discover recoverable session manifest during live start/stop/interruption and clean only after durable finalization/cancel policy.
- Replace automatic Finder reveal with a post-recording action model/surface offering Edit (truthfully disabled with reason until media Studio exists), Copy/Drag, Save, and Reveal.
- Deterministic controller tests using injected service/recovery seams; no live permissions required.

## Truth and gate

Do not enable Edit until Phase 4 can open the recording. Gate: pause/resume/cancel/low-space/denial/interruption transitions are real and tested; completed state follows durable media only; full tests/build pass.
