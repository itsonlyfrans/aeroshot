# WP-05 controller — Focused media core

## Mission

Implement the non-destructive media kernel for the focused Video/GIF Studio without building a general NLE.

## Allowed files

- `Aeroshot/MediaStudio/Core/**`
- `AeroshotTests/MediaTimelineTests.swift`
- `_bmad-output/evolution/test-reports/WP-05-media-core.md`

Do not edit project schema, recording, annotation/editor, export, themes, history, UI, or project.pbxproj.

## Required implementation

- Codable composition model referencing immutable source assets with rational times.
- Pure operations for trim, split, and selected-range deletion with explicit first-slice ripple semantics.
- Playback mapping source↔composition time, frame-step calculation, J/K/L transport intent, and timecode formatting.
- Timed overlay ranges, crop/canvas state, audio mute/gain state, and disposable thumbnail/waveform request models.
- AVFoundation composition compiler that validates source duration/ranges and produces `AVMutableComposition` for current operations.
- Property/deterministic tests for timeline algebra, boundary/zero-duration cases, multiple edits, mapping reversibility, and invalid media.

## Truth and gate

No reorder, freeze/speed, polished UI, thumbnail decoder, or export claim. Gate: timeline algebra/property tests pass and compiled compositions preserve source immutability.
