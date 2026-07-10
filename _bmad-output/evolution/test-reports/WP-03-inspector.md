# WP-03 — Selection-aware inspector verification

Date: 2026-07-10

## Implemented

- Selection-aware editor inspector backed by `EditorDocument.transformAnnotation` and `ModifyAnnotationCommand`.
- Validated numeric controls for stroke width/opacity, fill opacity, dash length/gap/phase, independent arrowhead length/width/inset/curve, corner radius, shadow opacity/radius/offset, font size, text background opacity/padding/line height.
- Pickers and direct controls for colors, fill, line cap, arrowhead start/end style, text, font family/weight/alignment, and text background.
- Explicit no-selection state that edits only the existing tool-default bindings.
- Bounds checking, non-finite input rejection, units, native keyboard-editable numeric fields, slider stepping, accessibility labels/values/adjustable actions, and source-order focus traversal.
- Unit tests for validation, property-to-appearance bindings, selection scoping, and exact undo/redo command generation.

## Automated evidence

- App build: **pass**
  - `xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
- Focused test command attempted:
  - `xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests/AnnotationInspectorTests test CODE_SIGNING_ALLOWED=NO`
- Focused tests: **pass, 5/5**.
- Full unit target: WP-03 and all pre-existing suites pass; the concurrently added `MediaTimelineTests.compilerBuildsRealCompositionWithoutMutatingSource()` test currently fails. This is outside WP-03's allowed files and has been routed to that work-package owner.

## Manual gates still required

- Verify VoiceOver announces each inspector section/control, its unit/value, and arrow-key adjustable actions.
- Verify Full Keyboard Access traversal follows the visible top-to-bottom order and focus remains visible in light/dark and increased-contrast modes.
- Verify Reduce Transparency uses the unified opaque panel fallback.
- Visually confirm an edited arrowhead renders its independent length, width, inset, and curve and survives project save/open.
