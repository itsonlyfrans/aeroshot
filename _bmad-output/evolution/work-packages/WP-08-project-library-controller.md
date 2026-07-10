# WP-08 controller — Local project library

## Mission

Evolve History into a dependable local library for images, recordings, GIFs, and editable projects with recovery state, search, tags, favorites, and truthful quick actions.

## Allowed files

- `Aeroshot/History/**`
- `AeroshotTests/ProjectLibraryTests.swift`
- `_bmad-output/evolution/test-reports/WP-08-project-library.md`

Preserve all pre-existing History user edits. Do not edit project/media/GIF bridges, editor/Studio, recording, themes, app state, export, or project.pbxproj.

## Required implementation

- Backward-compatible library item/store schema for capture kind, project/export URLs, tags, favorite, recovery/missing-source state, checksums, dimensions/duration, and last-opened.
- Atomic local persistence, search/filter/sort, duplicate/missing reconciliation, recovery discovery inputs, and safe delete-to-Trash semantics.
- History UI states/actions for open/edit, copy/drag, reveal, recover, favorite, tags, delete; disable unavailable actions with reasons.
- Deterministic store/migration/search/reconciliation/trash tests; accessibility labels/keyboard focus and empty/error states.

## Truth and gate

No cloud/account. Gate: existing history migrates, all local artifact kinds index/reopen/recover truthfully, tests/build pass.
