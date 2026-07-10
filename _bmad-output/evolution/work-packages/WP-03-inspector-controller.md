# WP-03 controller — Selection-aware inspector

## Mission

Expose direct and numeric editing for the selected annotation using the unified design system, with arrowhead size as the canonical precision workflow.

## Allowed files

- `Aeroshot/Editor/EditorWindowController.swift`
- `Aeroshot/Editor/AnnotationInspector.swift`
- `AeroshotTests/AnnotationInspectorTests.swift`
- `_bmad-output/evolution/test-reports/WP-03-inspector.md`

Do not edit annotation model/renderer, canvas, undo/document, project schema/bridge, themes, recording, or project.pbxproj.

## Required implementation

- Selection-aware inspector whose edits mutate selected objects through undoable document commands.
- Numeric fields plus appropriate sliders/pickers for stroke, opacity, fill, dash, arrow start/end and independent length/width/inset/curve, corner radius, shadow, and text controls.
- Explicit empty/no-selection state, validation, units, keyboard stepping, meaningful accessibility labels/values/actions, and focus order.
- Existing tool defaults remain available when nothing is selected, without silently overwriting selection.
- Tests for bindings/validation/undo command generation independent of visual inspection.

## Truth and gate

No mixed multi-selection values until multi-select exists. Gate: selected-property edits round-trip through project bridge and render via the shared appearance model; tests/build pass.
