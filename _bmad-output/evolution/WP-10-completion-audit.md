# Aeroshot product-evolution completion audit

Date: 2026-07-10

This audit treats every Phase 1–7 plan line as incomplete until direct code, test, or release evidence proves it. A green build alone is not accepted as proof.

## Proven implementation

- Phase 1: shared semantic design system; versioned atomic `.aeroshot` package kernel; migrations, recovery, media-compatibility policy, screenshot bridge, and round-trip tests.
- Phase 2: tool-specific geometry/hit testing, typed appearance, precise inspector, selection/move/resize/z-order/nudge, templates, explicit crop apply/cancel, aspect constraints, adjustable crop handles, persisted straighten, and renderer/persistence tests.
- Phase 3: displayed recording preflight, pause/resume timestamp correction, selectable microphone, system/microphone meters, HUD state/hotkeys, bounded normalized cursor/click metadata sidecar, effect policy, recovery manifest, low-space/failure handling, post-capture actions, and deterministic synchronization tests.
- Phase 4: playback/transport/timecode/thumbnails, trim/split/delete, timed callouts, crop, audio mute/gain/fades/waveform, editable cursor/click emphasis with retimed persisted events, cancellable export/progress/H.264/HEVC/size estimates, persisted fades, and offline timed-callout/effect content. Webcam remains truthfully identified as baked when no separate stream exists.
- Phase 5: bounded disk spool, exact timing/loop/ping-pong/frame editing, persisted crop/speed/timed annotations, palette/dither/transparency/coalescing/estimates, streaming changed-region delta encoding, documentation/social preset comparison, atomic export, and decoder-readback regression tests.
- Phase 6: searchable tagged/favorite/recovery-aware local project library; typed automation router and URL/Shortcuts/AppleScript/CLI boundaries; export recipes; default-off content-free telemetry; entitlement isolation; build/security/privacy/distribution/release documentation.
- Phase 7: deterministic golden corpus, package/annotation/timeline/GIF/export benchmarks, XCTest CPU/memory baselines, signed UI automation and permission matrix, consented local diagnostics, reliability tests, and content-free beta scorecard aggregation.
- UITestRunner: Developer Mode enabled, runner kept signed, guarded script added, signed UI suite passed 6/6.

## Remaining evidence or implementation gaps

1. Preview/export parity now has representative Retina and ultrawide export coverage, but the new UI visual fixtures still require a successful signed run after the desktop accessibility shield is cleared.
2. VoiceOver, keyboard-only, localization expansion, live permission permutations, capture latency, live A/V energy, notarization, and oldest-supported-hardware measurements remain manual/external release gates. Oldest-hardware measurement was explicitly deferred by the product owner.
3. The beta scorecard implementation exists, but actual cohort outcomes require external participants and cannot be fabricated as repository evidence.
4. Final security-diff review was opened in the native Codex Security workspace; the continuation tool is currently unavailable, so no scan result is claimed.

## Current automated evidence

- Complete `AeroshotTests`: implementation tests pass; the latest complete run had one unrelated diagnostics file-permission transient which passed immediately in isolation, so a clean full-suite rerun remains required.
- `PerformanceReleaseTests`: 7/7 pass.
- `PerformanceMetricTests`: 2/2 pass with clock/CPU/memory metrics.
- Signed `AeroshotUITests`: previously 6/6 pass; rerun required after the new preflight/crop work.
- Debug build: pass; universal arm64/x86_64 Release build passes after the new work.

The persistent goal must remain active until the implementation gaps above are closed or an explicit product-owner deferral removes them from the requested end state.
