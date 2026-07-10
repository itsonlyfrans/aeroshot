# Aeroshot product-evolution completion audit

Date: 2026-07-10

This audit treats every Phase 1–7 plan line as incomplete until direct code, test, or release evidence proves it. A green build alone is not accepted as proof.

## Proven implementation

- Phase 1: shared semantic design system; versioned atomic `.aeroshot` package kernel; migrations, recovery, media-compatibility policy, screenshot bridge, and round-trip tests.
- Phase 2: tool-specific geometry/hit testing, typed appearance, precise inspector, selection/move/resize/z-order/nudge, templates, explicit crop apply/cancel, aspect constraints, adjustable crop handles, persisted straighten, and renderer/persistence tests.
- Phase 3: displayed recording preflight, pause/resume timestamp correction, selectable microphone, system/microphone meters, HUD state/hotkeys, effect policy, recovery manifest, low-space/failure handling, post-capture actions, and deterministic synchronization tests.
- Phase 4: playback/transport/timecode/thumbnails, trim/split/delete, timed callouts, crop, audio mute/gain/fades/waveform, cancellable export/progress/H.264/HEVC/size estimates, persisted fades, and offline timed-callout content.
- Phase 5: bounded disk spool, exact timing/loop/ping-pong/frame editing, persisted crop/speed/timed annotations, palette/dither/transparency/coalescing/estimates, documentation/social preset comparison, atomic export, and regression tests.
- Phase 6: searchable tagged/favorite/recovery-aware local project library; typed automation router and URL/Shortcuts/AppleScript/CLI boundaries; export recipes; default-off content-free telemetry; entitlement isolation; build/security/privacy/distribution/release documentation.
- Phase 7: deterministic golden corpus, package/annotation/timeline/GIF/export benchmarks, XCTest CPU/memory baselines, signed UI automation and permission matrix, consented local diagnostics, reliability tests, and content-free beta scorecard aggregation.
- UITestRunner: Developer Mode enabled, runner kept signed, guarded script added, signed UI suite passed 6/6.

## Remaining evidence or implementation gaps

1. GIF export coalesces identical frames but does not yet encode changed-region/delta rectangles.
2. Video Studio exposes crop/callouts/audio, but editable cursor/click/webcam presentation and automatic zoom controls are not yet wired from recorded event tracks through preview and export. Baked fallback is implemented and documented.
3. Preview/export parity is covered structurally and by export tests, but representative Retina and ultrawide rendered golden comparisons are not yet present.
4. The Phase 1 light/dark/increased-contrast/reduced-motion visual fixtures exist as design/audit captures and UI accommodations are tested, but there is no pixel-diff visual-regression runner.
5. VoiceOver, keyboard-only, localization expansion, live permission permutations, capture latency, live A/V energy, notarization, and oldest-supported-hardware measurements remain manual/external release gates. Oldest-hardware measurement was explicitly deferred by the product owner.
6. The beta scorecard implementation exists, but actual cohort outcomes require external participants and cannot be fabricated as repository evidence.
7. Final security-diff review was opened in the native Codex Security workspace; the continuation tool is currently unavailable, so no scan result is claimed.

## Current automated evidence

- Complete `AeroshotTests`: pass after the stricter gap fixes.
- `PerformanceReleaseTests`: 7/7 pass.
- `PerformanceMetricTests`: 2/2 pass with clock/CPU/memory metrics.
- Signed `AeroshotUITests`: previously 6/6 pass; rerun required after the new preflight/crop work.
- Debug build: pass; Release rerun required after the new work.

The persistent goal must remain active until the implementation gaps above are closed or an explicit product-owner deferral removes them from the requested end state.
