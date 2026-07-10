# WP-06 controller — Media render snapshot and export

## Mission

Implement cancellable MP4 export around one immutable project/render snapshot with progress, presets, size estimation, and explicit hardware/fallback evidence.

## Allowed files

- `Aeroshot/Export/Media/**`
- `AeroshotTests/MediaExportTests.swift`
- `_bmad-output/evolution/test-reports/WP-06-media-export.md`

Do not edit project schema, media timeline core, annotation/editor, recording, themes, UI, or project.pbxproj.

## Required implementation

- Immutable export snapshot types consuming project asset/timeline/overlay data without live editor state.
- H.264/HEVC presets, resolution/frame-rate validation, deterministic size estimate with stated uncertainty, and color-space policy.
- Async cancellable export coordinator using AVFoundation with progress available promptly, atomic destination replacement, partial cleanup, and typed failure/cancellation.
- Overlay compilation boundary shared by preview/export data; use offline Core Animation tool where valid and keep preview backend separate but snapshot-identical.
- Hardware-encoder preference/fallback status visible in result/evidence rather than silently claimed.
- Deterministic unit tests plus small generated AVFoundation fixture when supported; cancellation and partial-file tests required.

## Truth and gate

No finished Studio/export-sheet UI claim. Gate: fixture export is valid/cancellable, progress/result truth is testable, preview/export consume the same snapshot.
