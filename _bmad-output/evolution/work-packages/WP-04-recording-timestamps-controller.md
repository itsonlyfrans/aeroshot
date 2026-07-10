# WP-04 controller — Recording pause/resume timestamps

## Mission

Add production pause/resume timestamp correction to the existing AVAssetWriter recording service without changing the default capture backend or macOS 14.6 deployment target.

## Allowed files

- `Aeroshot/Recording/ScreenRecordingService.swift`
- `Aeroshot/Recording/RecordingTimelineClock.swift`
- `AeroshotTests/RecordingTimelineTests.swift`
- `_bmad-output/evolution/test-reports/WP-04-recording-timestamps.md`

Do not edit RecordingController, GIF service, project schema, session-kernel files, UI, themes, or project.pbxproj.

## Required implementation

- Thread-safe pause/resume API and state appropriate for ScreenCaptureKit callbacks.
- One canonical correction clock that subtracts paused intervals from video, system-audio, and microphone timestamps while preserving monotonicity and their relative alignment.
- Samples received while paused are not appended; resume cannot create a duration jump.
- Deterministic pure timestamp tests covering multiple pauses, audio/video/mic alignment, non-zero first timestamps, pause before first sample, invalid transition idempotence, and long-duration rational precision.
- Preserve current start/stop/cancel behavior and writer finalization.

## Truth and gate

Do not claim device/UI integration. Gate: focused/full tests and build pass; corrected tracks remain monotonic and aligned within deterministic rational-time assertions.
