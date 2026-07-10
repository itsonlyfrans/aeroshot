# WP-03 selection and transform controller — validation report

Date: 2026-07-10
Status: Passed

## Implemented

- Tool-specific, zoom-stable selection handles and deterministic handle hits.
- Live move and endpoint/bounding-object resize previews with one command committed per completed gesture.
- Image-bound clamping, minimum non-degenerate geometry, and no-op command suppression.
- Stable-ID delete, 1 px arrow nudge, 10 px Shift-arrow nudge, Escape cancellation, and z-order commands (`Command-[`, `Command-]`; Shift sends to edge).
- Exact undo/redo for transforms and z-order, including redo invalidation after a new command.
- Deferred multi-select, rotate, grouping, and advanced alignment were not implemented.

## Validation

- Focused: `xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests/AnnotationTransformTests test CODE_SIGNING_ALLOWED=NO`
  - Passed: 7 tests.
- Full unit target: `xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests test CODE_SIGNING_ALLOWED=NO`
  - Passed with no failures.
- Build: `xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
  - Passed.

Gate result: current annotation tools still compile and their existing engine tests pass; release-critical single-selection transforms are deterministic and undoable.
