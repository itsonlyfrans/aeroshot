# WP-05 — Media project bridge gate report

## Scope implemented

- Added a backward-compatible optional `mediaComposition` manifest section; all existing screenshot fields and defaults remain unchanged.
- Added exact rational-time persistence for slice identity/ranges, timed overlays, normalized crop and canvas pixels, audio state, and named media export presets including codec and target bitrate.
- Added checksum-validated MP4 and GIF import to immutable `assets/originals` without transcoding.
- Added exact bidirectional mapping between package state and `MediaCompositionModel`, with source type/duration/URL, range, crop, audio, preset, and duplicate-ID validation.
- Added reopen/save behavior that retains editable slices and overlays while package-store immutability checks preserve original metadata, bytes, and checksum.

## Automated coverage

`MediaProjectBridgeTests` covers:

- MP4 import and exact trim/split/delete, timed overlay, canvas/audio, and export-preset round trip.
- GIF import, edit/reopen round trip, exact duration, and unchanged source bytes.
- Missing, truncated/corrupt, and wrong-media-type source rejection.
- Invalid persisted source range and missing duration rejection.
- Decoding a screenshot manifest with no media section using backward-compatible defaults.

## Gate evidence

- Debug application build with code signing disabled: **passed** (`xcodebuild ... build`, 2026-07-10).
- Focused `MediaProjectBridgeTests`: **5/5 passed** (MP4, GIF, error handling, invalid data, screenshot compatibility).
- Complete `AeroshotTests` unit-test bundle: **passed** (`xcodebuild test ... -only-testing:AeroshotTests`).
- The UI runner host issue was subsequently resolved by enabling Developer Mode and rebuilding with signing enabled; the guarded focused UI smoke test passes 1/1. See `WP-09-ui-runner.md`.

Gate: **passed**. Media projects round-trip exactly and immutable original bytes/checksums remain unchanged.
