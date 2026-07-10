# WP-01 controller — Existing editor project adapter

## Mission

Close the Phase 1 gate by making the current screenshot editor save and reopen losslessly through the real `AeroProjectPackageStore`, without adding a mandatory step to instant capture or changing rendered output.

## Allowed files

- `Aeroshot/Project/AeroProject.swift`
- `Aeroshot/Project/EditorProjectBridge.swift`
- `Aeroshot/Editor/EditorWindowController.swift`
- `AeroshotTests/EditorProjectBridgeTests.swift`
- `_bmad-output/evolution/test-reports/WP-01-editor-adapter.md`

Do not modify annotation rendering, canvas interaction, design-system files, capture, recording, export internals, project.pbxproj, or existing project-kernel tests.

## Required implementation

- Extend the schema only with backward-compatible optional/defaulted fields needed to losslessly represent every current annotation kind, text/font/step/fill data, crop, and beautify settings.
- Bridge a live `EditorDocument` to an atomic local package with a PNG immutable original and back again.
- Preserve annotation IDs/order, points, colors/alpha, widths, text, font size, step number, fill, crop, and beautify settings.
- Add explicit Open Project and Save Project entry points in the editor controller/API without changing existing image-open or PNG export paths.
- Reject missing/wrong-type/corrupt source assets through typed errors; never silently flatten edits.
- Round-trip tests for all current annotation kinds, crop, beautify, immutable-source checksum, and corrupt/missing source behavior.

## Truth and gate

This is screenshot-project persistence only. Do not claim media Studio/timeline UI. Gate: current instant image open/export is unchanged, screenshot project round-trip is lossless, full tests/build pass.
