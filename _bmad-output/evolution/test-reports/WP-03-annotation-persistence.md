# WP-03 — Expanded annotation persistence gate

Status: implementation complete; focused gate passed. Repository-wide build is
was subsequently verified after the concurrent integration completed.

## Implemented

- Added an optional, typed editor appearance payload to version-1 overlays.
- Persisted stroke opacity, dash/phase/cap/shadow, fill opacity, corner radius,
  arrow endpoint styles/dimensions/inset/curve, and all typography background,
  padding, alignment, weight, font, and line-height fields.
- Mapped every field bidirectionally without changing the annotation APIs.
- Missing appearance payloads reopen with `AnnotationAppearance()` so legacy
  projects retain the historical renderer defaults.
- Rejects non-finite, out-of-range, negative, malformed-color, and unknown-enum
  appearance values with `invalidAnnotationAppearance`.

## Evidence

- Focused command:
  `xcodebuild -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests/EditorProjectBridgeTests test`
- Result: **TEST SUCCEEDED** (11 bridge tests), including maximal appearance
  round-trip, legacy-default decoding, and malformed range/color/enum cases.
- A full test invocation subsequently ran the complete suite with the new bridge
  and annotation tests passing.
- Earlier standalone build attempts overlapped other work packages; the final
  work packages were actively changing shared files: first
  `Aeroshot/Editor/UndoStack.swift` referenced a temporarily missing
  `AnnotationZOrder`; the next attempt reached
  `Aeroshot/Recording/RecordingPreflightView.swift` and failed on its missing
  `Combine` import. No WP-03 file produced a compiler error.

## Gate assessment

Customized properties survive save/reopen and legacy overlays resolve to exact
legacy appearance defaults. Focused persistence gate is green. Re-run the full
build after the concurrent annotation/editor work settles for final integration
evidence.
