# WP-05 controller — Media project bridge

## Mission

Make completed recordings real editable `.aeroshot` projects by bridging immutable video assets, timeline edits, timed overlays, canvas/audio state, and export presets between `AeroProjectPackageStore` and the media core.

## Allowed files

- `Aeroshot/Project/AeroProject.swift`
- `Aeroshot/Project/MediaProjectBridge.swift`
- `AeroshotTests/MediaProjectBridgeTests.swift`
- `_bmad-output/evolution/test-reports/WP-05-media-project-bridge.md`

Do not edit screenshot bridge, package store/migrator, media core/export, recording, UI, annotations, themes, or project.pbxproj.

## Required implementation

- Import MP4/GIF as checksum-validated immutable original assets without destructive transcoding.
- Backward-compatible schema fields for exact media composition slices, timed overlays, crop/canvas, audio, and media export presets.
- Exact bidirectional mapping to media-core rational time, with source-duration/type validation and future/invalid data rejection.
- Reopen projects with edits editable; preserve source bytes/checksum across saves.
- Tests for MP4/GIF round trip, trim/split/delete, timed overlay, canvas/audio, presets, missing/wrong/corrupt sources, and source immutability.

## Truth and gate

No Studio UI claim. Gate: media projects round-trip exactly and originals remain unchanged; full tests/build pass.
