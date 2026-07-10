# WP-06 — Focused Video Studio UI

Date: 2026-07-10

## Implemented

- Main-actor Video Studio document owning a real `AVPlayer`, compiled `AVMutableComposition`, immutable export inputs, command history, and package persistence through `MediaProjectBridge`.
- Post-recording Edit availability checks, recovery explanation, and native Studio window handoff.
- Native SwiftUI/AppKit preview, transport, exact timecode, seekable thumbnail timeline, In/Out selection, split, first-slice range deletion, trim, undo/redo, timed callout list/inspector, crop essentials, mute/gain, export progress/cancellation/result reveal.
- Space, J/K/L, arrow frame step, I/O, Delete, and Command-Z/Shift-Command-Z commands with accessible labels, named timeline actions, stable UI identifiers, and reduced-motion handling.
- Export flattens the exact compiled edit composition, then sends that immutable source plus canvas/timed-overlay snapshot through `MediaExportCoordinator`; no fake media commands are enabled.
- Deterministic command/model coverage in `VideoStudioModelTests`.

## Automated evidence

- Debug application build with signing disabled: passed (`BUILD SUCCEEDED`).
- Focused `VideoStudioModelTests`: 4/4 passed (`TEST SUCCEEDED`).
- Full `AeroshotTests` unit suite: passed (`TEST SUCCEEDED`).
- Freshly signed focused UI smoke test through the guarded runner: 1/1 passed in 2.523 seconds.
- Warnings observed are pre-existing deprecation/unused-result warnings in media export and recording service code outside WP-06 file ownership.

## Manual / visual gates

The implementation is ready for manual validation with a freshly recorded MP4. The following hardware/UI gates require an interactive signed app run and are not claimed by automated model tests:

1. Confirm MP4 opens and audio/video remain synchronized after removing a mistake.
2. Confirm callout timing and crop visually match the exported MP4.
3. Save, close, reopen the `.aeroshot` package, and confirm edits persist.
4. Exercise export cancellation on a long recording and confirm no partial destination remains.
5. Keyboard-only and VoiceOver pass across preview, timeline, inspector, and export state.

The reported “UITestRunner is damaged and can’t be opened” alert is resolved. Developer Mode was enabled and a freshly signed runner executed through the guarded UI-test script; the focused UI smoke test passed 1/1 in 2.523 seconds.
