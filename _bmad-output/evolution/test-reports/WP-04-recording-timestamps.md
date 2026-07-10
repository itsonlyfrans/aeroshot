# WP-04 recording timestamp gate

Date: 2026-07-10  
Scope: `ScreenRecordingService` pause/resume timestamp correction only

## Implemented evidence

- `ScreenRecordingService.pause()` and `resume()` use lock-protected transition state shared with ScreenCaptureKit callbacks.
- Paused callbacks are rejected before entering the writer queue.
- The first accepted sample after resume closes the pause using source media time; no wall-clock or floating-point conversion is used.
- One `RecordingTimelineClock` subtracts the canonical accumulated paused duration from video, system-audio, and microphone timestamps.
- Presentation and decode timestamps receive the same correction; sample durations are preserved.
- Per-track monotonic guards preserve each track's ordering without destroying relative A/V/microphone offsets.
- Existing AVAssetWriter setup, lazy inputs, stop, cancel, no-frame handling, and finalization paths remain in place.

## Deterministic gate results

Focused command:

```text
xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:AeroshotTests/RecordingTimelineTests \
  CODE_SIGNING_ALLOWED=NO
```

Result: **PASS**, 7/7 tests. Covered multiple pauses, exact three-track alignment, non-zero first timestamp, pause before first sample, invalid-transition idempotence, per-track monotonicity, and exact 90 kHz rational arithmetic through 72 hours.

Full unit command:

```text
xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:AeroshotTests CODE_SIGNING_ALLOWED=NO
```

Result: **PASS**, 102/102 tests.

Build command:

```text
xcodebuild build -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

Result: **PASS** for the macOS 14.6 deployment target.

An additional unfiltered scheme test compiled and passed all 102 unit tests, but the UI-test runner was killed before establishing its test connection after 153.870 seconds. This is not a timestamp assertion failure, but it means the unfiltered UI scheme is not claimed as passing.

## Gate decision and limitations

The deterministic timestamp gate is **PASS**: corrected tracks are exact, monotonic per track, and aligned by one rational correction clock. The build and complete unit suite pass.

No device recording, HUD control, UI integration, interruption flow, or captured-file A/V drift measurement is claimed by this work package. The pause/resume service API is production-wired internally but remains unavailable to users until the recording session/controller and HUD work packages call it. Hardware capture and UI-runner evidence remain integration gates.
