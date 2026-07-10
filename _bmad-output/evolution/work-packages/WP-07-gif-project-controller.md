# WP-07 controller — GIF project persistence

## Mission

Persist the complete editable `GIFDocument` through `.aeroshot` packages so timing, ranges, loop, ping-pong, resize, palette, dither, transparency, quality, and size-estimate inputs survive reopen.

## Allowed files

- `Aeroshot/Project/AeroProject.swift`
- `Aeroshot/Project/GIFProjectBridge.swift`
- `AeroshotTests/GIFProjectBridgeTests.swift`
- `_bmad-output/evolution/test-reports/WP-07-gif-project.md`

Do not edit screenshot/media bridges, package store, GIF core/writer/service, UI, history, themes, or project.pbxproj.

## Required implementation

- Backward-compatible optional GIF edit schema with exact integer/microsecond data and enum validation.
- Import existing GIF as immutable original plus bounded-spool/editor metadata without copying generated cache into ownership-critical state.
- Exact bidirectional mapping; source checksum remains stable across edits/saves.
- Tests for every timing/loop/quality field, edited ranges, legacy defaults, corrupt/missing/wrong source, malformed values, and immutability.

## Truth and gate

No UI claim. Gate: all GIF controls survive reopen exactly, invalid values fail typed validation, full tests/build pass.
