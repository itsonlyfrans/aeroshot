# WP-07 GIF project persistence — gate report

Date: 2026-07-10  
Status: PASS

## Implemented contract

- Added the backward-compatible optional `gifEditState` manifest field. Existing screenshot and media manifests decode with `nil` and retain their existing fields.
- Persisted every editable `GIFDocument` value: stable frame IDs, exact integer microsecond durations, loop mode/count, ping-pong, output dimensions, palette, dither, transparency, and full `Double` quality.
- Added typed schema validation for empty/duplicate/invalid frames, unsafe derivative paths, duration overflow, invalid loop counts, dimensions, palette, quality, and spool bounds.
- Imported GIF bytes once as the immutable original asset. Decoded PNG frames live only under `generated/gif-frames` and are not package assets or ownership-critical state.
- Persisted immutable-source frame indices so purgeable derivatives for trimmed or duplicated documents can be reconstructed without changing edited durations or IDs.
- Preserved source asset checksum, byte count, metadata, and bytes across edit/save/reopen.

## Automated evidence

Focused command:

`xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests/GIFProjectBridgeTests CODE_SIGNING_ALLOWED=NO`

Result: **TEST SUCCEEDED**, 7/7 tests.

Coverage includes:

- exact edited-range and timing round trips;
- every loop form and every export/size-estimate input;
- legacy defaults and screenshot-schema compatibility;
- generated-cache purge/rebuild after trimming;
- missing, corrupt, wrong-type, and mutable source rejection;
- typed malformed-value validation;
- frame-count/byte spool bounds and unsupported input.

Full unit command:

`xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests CODE_SIGNING_ALLOWED=NO`

Result: **TEST SUCCEEDED**. This includes the GIF Studio controller integration test using the project bridge.

Build command:

`xcodebuild build -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

Result: **BUILD SUCCEEDED**.

## Runner note

The host runner issue was subsequently resolved by enabling Developer Mode and rebuilding with signing enabled. The guarded focused UI smoke test passes 1/1; see `WP-09-ui-runner.md`. No UI claim is part of this work package.
