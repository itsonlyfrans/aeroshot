# WP-03 controller — Selection, resize, z-order, and keyboard precision

## Mission

Implement the release-critical transform subset on the current editor: select, move, resize, z-order, precise keyboard nudging, undo/redo, and accessible numeric command seams.

## Allowed files

- `Aeroshot/Editor/EditorCanvasView.swift`
- `Aeroshot/Editor/EditorDocument.swift`
- `Aeroshot/Editor/UndoStack.swift`
- `Aeroshot/Editor/Selection/**`
- `AeroshotTests/AnnotationTransformTests.swift`
- `_bmad-output/evolution/test-reports/WP-03-selection-transform.md`

Do not edit annotation model/renderer, editor window/inspector, project bridge/schema, themes, recording, or project.pbxproj.

## Required implementation

- Selection handles from tool-specific geometry; pointer resize for line endpoints and bounding objects.
- Move/resize commands committed once per gesture with live preview and exact undo/redo.
- Arrow-key nudge, Shift accelerated nudge, delete, escape, and z-order commands with stable IDs.
- Clamp/degenerate rules that prevent invalid geometry and keep controls usable at zoom.
- Tests for commands, handle hit selection, transforms, z-order, keyboard deltas, redo invalidation, and no-op gestures.

## Truth and gate

Multi-select, rotate, grouping, and advanced alignment remain deferred. Gate: current tools still draw; release-critical transforms are deterministic and undoable.
