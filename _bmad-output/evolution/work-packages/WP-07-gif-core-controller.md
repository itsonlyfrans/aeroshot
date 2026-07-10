# WP-07 controller — Bounded GIF capture and optimization core

## Mission

Replace duration-scaled full-frame memory capture with a bounded spool and implement editable, deterministic GIF timing/loop/quality export foundations reusable by GIF Studio.

## Allowed files

- `Aeroshot/Recording/GIFRecordingService.swift`
- `Aeroshot/GIFStudio/Core/**`
- `AeroshotTests/GIFStudioTests.swift`
- `_bmad-output/evolution/test-reports/WP-07-gif-core.md`

Do not edit project schema/bridge, media core/export, recording controller/session, UI, editor, themes, history, or project.pbxproj.

## Required implementation

- Bounded disk-backed frame or intermediate-video spool with cleanup/recovery and no full-duration `[CGImage]` retention.
- Exact frame/range timing, trim/split/delete, duplicate/delete, loop once/count/forever, ping-pong model, resize, palette size, dither, transparency, duplicate-frame coalescing, and size estimate.
- ImageIO writer uses unclamped delay for sub-100ms targets and records effective timing/loop metadata.
- Deterministic generated-frame tests for metadata, timing, loop, spool bounds/cleanup, memory-shape invariant, resize, palette/quality, cancellation, and output size estimate.

## Truth and gate

Changed-region optimization may be deferred if not implemented; do not fake live preview. Gate: 60-second-equivalent fixture is duration-bounded in memory, editable timing survives model round trip, valid optimized GIF exports; full tests/build pass.
