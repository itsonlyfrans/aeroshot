# WP-03 controller — Annotation geometry and appearance

## Mission

Upgrade annotations from shallow marks to typed editable objects while preserving legacy initializer/call-site behavior and exact current rendering defaults.

## Allowed files

- `Aeroshot/Editor/Annotation.swift`
- `Aeroshot/Editor/AnnotationGeometry.swift`
- `Aeroshot/Editor/Rendering/AnnotationRenderer.swift`
- `Aeroshot/Editor/Tools/AnnotationTool.swift`
- `AeroshotTests/AnnotationEngineTests.swift`
- `_bmad-output/evolution/test-reports/WP-03-annotation-engine.md`

Do not edit canvas/window UI, undo/document, project schema/bridge, recording, themes, or project.pbxproj.

## Required implementation

- Typed appearance: stroke/fill opacity, dash, shadow, corner radius, typography/alignment/background/padding/line height.
- Independent arrow start/end styles, head length, head width, inset, and curve with legacy defaults matching current output.
- Tool-specific geometry paths, bounds, handles, and hit tests for line/freehand/arrow, shapes, text/step, and redaction.
- Deterministic renderer helpers shared by preview/export and geometry tests for degenerates, zoom-independent tolerance inputs, arrowheads, opacity/dash, bounds, and hit tests.
- Preserve every existing tool and source-compatible initializer default.

## Truth and gate

No transform UI or inspector claim. Gate: existing tests/build pass, new geometry/property tests pass, legacy render defaults remain equivalent.
