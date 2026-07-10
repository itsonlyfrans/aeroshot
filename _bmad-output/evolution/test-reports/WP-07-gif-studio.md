# WP-07 — GIF Studio UI verification

Status: complete for the work-package implementation and unit/build gates.

## Delivered

- Main-actor GIF Studio document with exact frame-range commands, deterministic undo/redo, debounced autosave, immediate save, and `.aeroshot` import/open/save through `GIFProjectBridge`.
- Preview decoding uses ImageIO thumbnails capped at 1,280 pixels and an `NSCache` capped at six decoded previews / 48 MiB. The document itself retains only `GIFFrame` URL/timing metadata.
- Atomic `GIFWriter` export with status, completion metadata, cancellation, and destination result.
- Accessible SwiftUI controls for selection, trim/split/delete/duplicate, timing, loop once/count/forever, ping-pong, dimensions, palette, dither, transparency, quality, and estimated-versus-actual size.
- Keyboard selection/edit/undo/redo/save commands, VoiceOver labels and selected traits, reduced-motion behavior, and explicit constrained-playback timing guidance.
- No changed-region optimization is implemented or claimed.

## Gate evidence

- 60-second project: `longProjectPreviewStateIsDurationIndependent` opens 600 × 100 ms frames while the decoded-preview cap remains six.
- Save/reopen: `controllerUsesProjectBridgeForImportSaveAndReopen` performs a real GIF import, edit, bridge save, and bridge reopen with exact timing/settings retained.
- Valid export: `modelPerformsRealSmallAtomicExport` validates GIF type, frame count, output URL, and byte count.
- Cancellable export: existing real writer integration `cancellationPreservesExistingDestinationAndRemovesPartial` verifies cancellation preserves the destination and removes partial files.
- Deterministic commands: model tests cover trim, split, delete, duplicate, range timing, settings, undo, and redo.

## Commands

```text
xcodebuild -project Aeroshot.xcodeproj -scheme Aeroshot -configuration Debug \
  -derivedDataPath /tmp/Aeroshot-WP07 build CODE_SIGNING_ALLOWED=NO
Result: BUILD SUCCEEDED

xcodebuild -project Aeroshot.xcodeproj -scheme Aeroshot \
  -derivedDataPath /tmp/Aeroshot-WP07 test \
  -only-testing:AeroshotTests/GIFStudioModelTests CODE_SIGNING_ALLOWED=NO
Result: TEST SUCCEEDED; 5/5 GIF Studio model/integration tests passed

xcodebuild -project Aeroshot.xcodeproj -scheme Aeroshot \
  -derivedDataPath /tmp/Aeroshot-WP07 test \
  -only-testing:AeroshotTests CODE_SIGNING_ALLOWED=NO
Result: all unit tests passed, including GIF core, bridge, controller, export, and cancellation tests
```

## UI-test runner note

The host issue was resolved after this work-package run: Developer Mode was enabled and the UI target was rebuilt with signing enabled. The guarded focused UI smoke test passes 1/1 in 2.523 seconds. `scripts/run-ui-tests.sh` now prevents the invalid unsigned-runner command path; see `WP-09-ui-runner.md`.
