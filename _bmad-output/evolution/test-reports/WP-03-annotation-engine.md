# WP-03 test report — Annotation geometry and appearance

Date: 2026-07-10

## Outcome

PASS. Annotations are now typed editable objects with deterministic image-space
geometry and renderer properties shared by live preview and export. The existing
initializer, tool set, call sites, and renderer defaults remain compatible.

This work does not add or claim transform UI or an appearance inspector.

## Implemented contract

- Added typed stroke and fill opacity, dash/phase, line cap, shadow, corner
  radius, typography, alignment, text background, padding, and line height.
- Added independent arrow start/end styles plus configurable head length, head
  width, shaft inset, and curve. Nil dimensions intentionally resolve to the
  historical line-width-dependent arrow formula.
- Added deterministic paths, rendered bounds, edit handles, and path-aware hit
  tests for line/freehand/highlighter/arrow, rectangle/ellipse, text/step, and
  redactions.
- Hit-test tolerance is an explicit image-space input. A canvas can divide its
  desired screen-point tolerance by zoom before calling the existing method;
  the no-argument legacy behavior remains a six-pixel tolerance.
- Preview and export continue through `AnnotationRenderer.draw`; that shared
  path now consumes `AnnotationGeometry` and the typed appearance.
- `ToolStyle` carries the typed appearance into every annotation-producing
  tool without adding or removing tools.

## Legacy compatibility evidence

- The original `Annotation` initializer labels and all original defaults are
  unchanged; the additive `appearance` parameter defaults to legacy output.
- Default rectangle corner radius remains 2 pixels.
- Default arrow output remains: no start head, filled end head,
  `max(lineWidth * 4, 14)` edge length, `.pi / 7` head angle, and a
  `headLength * 0.6` shaft inset.
- Default text remains system semibold and retains the previous `+8` width and
  `+4` height bounds. The renderer takes the original CoreText path when the
  typography value is default.
- Default highlighter remains three times the stored width, 40% alpha, multiply
  blend mode.
- A deterministic bitmap test compares the former arrow algorithm with the new
  renderer byte for byte.

## Automated verification

Focused annotation suite:

```text
xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:AeroshotTests/AnnotationEngineTests

Result: TEST SUCCEEDED — 10/10 focused tests passed.
```

Focused coverage includes initializer/default equivalence, degenerate geometry,
zoom-independent tolerance inputs, precise line/freehand/shape/redaction hits,
handles, independent and curved arrowheads, custom dimensions, typography
bounds, rendered opacity/dash pixels, and byte-equivalent legacy arrow output.

Bridge and adjacent editor regression:

```text
xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:AeroshotTests/AnnotationEngineTests \
  -only-testing:AeroshotTests/EditorProjectBridgeTests \
  -only-testing:AeroshotTests/AeroshotTests

Result: TEST SUCCEEDED.
```

Full unit regression:

```text
xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:AeroshotTests

Result: TEST SUCCEEDED — 130 logical tests / 134 test runs passed.
```

Application build:

```text
xcodebuild build -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS,arch=arm64'

Result: BUILD SUCCEEDED with no warnings or errors.
```

`git diff --check` also passed for every WP-03 implementation and test file.

## Project bridge integration note

Default-valued annotations remain bridge-compatible now: the existing bridge
reconstructs `AnnotationAppearance()` and its screenshot project round-trip
tests pass. Customized appearance is intentionally not claimed as persisted,
because WP-03 forbids editing the project schema or bridge.

A later schema/bridge integration pass must map these additive fields:

- stroke opacity, dash lengths, dash phase, line cap, and shadow color/opacity/
  radius/offset;
- fill opacity and corner radius;
- arrow start/end style, head length, head width, inset, and curve;
- typography font name, weight, alignment, background color/opacity, padding,
  and line-height multiplier.

The current bridge already maps annotation color/alpha, width, filled state,
text, font size, step number, geometry points, ID, kind, and z-order. A single
overlay opacity cannot losslessly represent the new independent stroke, fill,
text-background, and shadow opacities, so these need explicit editor fields or a
versioned typed appearance object rather than lossy folding.

## Gate decision

WP-03 annotation-engine gate: PASS.

- Existing tests and application build: pass.
- New deterministic geometry/property tests: pass.
- Legacy initializer and renderer defaults: preserved, with byte-equivalence
  evidence for the most geometry-sensitive legacy primitive.
- No transform UI or inspector claim was introduced.
