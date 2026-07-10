# WP-01 test report — Existing editor project adapter

Date: 2026-07-10

## Outcome

PASS. The existing screenshot editor now has an explicit, lossless project-package adapter and controller API. Instant `open(image:)` and the existing flattened PNG/image export actions remain separate and unchanged.

This work is screenshot-project persistence only. It does not add or claim Studio, media timeline, or video editing UI.

## Implemented contract

- New packages are assembled in a sibling temporary directory, written through `AeroProjectPackageStore`, then moved into place only after the immutable PNG original and atomic manifest save succeed.
- Existing packages reuse the immutable original and reject attempts to bind editor state to different source pixels.
- Annotation ID, array order, kind, pixel-space points, sRGB color/alpha, width, text, font size, step number, and fill state round-trip exactly for all 11 current annotation kinds.
- Exact pixel-space crop and every current beautify field round-trip through backward-compatible optional manifest fields.
- Missing, checksum-invalid, wrong-media-type, non-PNG, corrupt, transformed/timed, and non-editor overlays are rejected through typed errors instead of being flattened.
- `EditorWindowController.openProject(at:appState:)`, `saveProject(to:)`, and `saveProject()` provide explicit non-flattened project entry points; existing image-open and export paths retain their prior signatures and behavior.

## Red/green evidence

The focused suite was added before implementation and initially failed to compile because `EditorProjectBridge`, its typed errors, and the optional manifest fields did not exist. After implementation and error-classification refinement:

```text
xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Aeroshot-WP01 \
  -only-testing:AeroshotTests/EditorProjectBridgeTests \
  CODE_SIGNING_ALLOWED=NO

Result: TEST SUCCEEDED — 8/8 focused tests passed.
```

Focused coverage:

- all current annotation kinds and every persisted annotation field;
- exact crop and beautify settings;
- immutable PNG checksum and byte preservation across reopen/save;
- backward-compatible defaults when editor manifest fields are absent;
- missing, wrong-type, and corrupt source assets;
- mutable-primary-source rejection;
- unsupported overlay rejection without flattening;
- immutable-source rebinding rejection.

## Regression and build evidence

```text
xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Aeroshot-WP01 \
  -only-testing:AeroshotTests \
  CODE_SIGNING_ALLOWED=NO

Result: TEST SUCCEEDED — 123/123 unit tests passed.
```

```text
xcodebuild build -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Aeroshot-WP01 \
  CODE_SIGNING_ALLOWED=NO

Result: BUILD SUCCEEDED.
```

## Gate decision

WP-01 editor-adapter gate: PASS.

- Current instant image open/export: unchanged.
- Screenshot project round-trip: lossless for the current editor model.
- Immutable source: checksum-validated and preserved.
- Corrupt or unsupported project input: typed failure, never silent flattening.
- Unit regression suite and application build: pass.
