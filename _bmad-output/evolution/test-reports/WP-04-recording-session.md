# WP-04 recording-session gate report

**Gate:** Passed for the domain/recovery kernel. Live UI and ScreenCaptureKit integration are outside this package and are not claimed.

## Delivered

- Typed recording source, dimensions, frame rate, cursor, system/microphone audio, webcam, countdown, event choices, permission/device readiness, and required-space estimate.
- Pure explicit state reducer covering idle, preflighting, countdown, recording, paused, stopping, completed, cancelled, failed, and recoverable interruption.
- Validated transitions with deterministic typed failures for permission denial, device loss, insufficient space, capture failure, and non-durable finalization.
- Idempotent cancellation: cleanup is emitted on the first active cancellation and not emitted again.
- Completion invariant: only `stopping + finalize(isDurable: true)` can produce `completed`; non-durable finalization produces `failed(.finalizationNotDurable)` and preserves recovery artifacts.
- Codable recovery manifest with schema validation, safe relative references, privacy retention, corrupt/expired filtering, and deterministic discovery order.
- Effect-capture policy and documented matrix for cursor, click, keystroke, and webcam metadata/fallback.

## Deterministic coverage

`AeroshotTests/RecordingSessionTests.swift` covers:

- zero-countdown and multi-tick countdown routes;
- pause/resume, stop from recording and paused, durable and non-durable finalization;
- denied/restricted/not-determined permissions, unavailable devices, and low disk space;
- interruption from recording, paused, and stopping, session mismatch rejection, and recovery;
- cancellation from idle, all active/recoverable states, and repeated cancellation;
- explicit failure from every active state and invalid-transition rejection;
- typed-value validation, manifest round trip, path traversal rejection, corrupt/expired discovery filtering, and deterministic sorting;
- all effect rows, metadata/fallback behavior, keystroke opt-in/indicator requirements, and secure-input exclusion.

## Validation evidence

Focused command:

```sh
xcodebuild -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' test \
  -only-testing:AeroshotTests/RecordingSessionTests CODE_SIGNING_ALLOWED=NO
```

Result: `** TEST SUCCEEDED **` on 2026-07-10; xcresult reports 19 passed executions, 0 failures, and 0 skips (15 declared tests, including one five-case parameterized test).

Full unit command:

```sh
xcodebuild -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' test \
  -only-testing:AeroshotTests CODE_SIGNING_ALLOWED=NO
```

Result: `** TEST SUCCEEDED **` on 2026-07-10.

The unrestricted scheme command executed the unit tests successfully but ended `TEST FAILED` because `AeroshotUITests-Runner` was killed before establishing its test connection. This is an external UI-runner bootstrap failure, not a WP-04 assertion or compile failure; the complete unit target is green.

This evidence is limited to the pure kernel and filesystem-fixture recovery discovery; it does not establish live capture, UI, permission prompting, timer, or durable-media adapter integration.
