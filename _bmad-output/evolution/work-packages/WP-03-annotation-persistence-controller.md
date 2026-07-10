# WP-03 controller — Expanded annotation persistence

## Mission

Persist every newly implemented typed annotation appearance/geometry field through `.aeroshot` packages without breaking version-1 projects or legacy default rendering.

## Allowed files

- `Aeroshot/Project/AeroProject.swift`
- `Aeroshot/Project/EditorProjectBridge.swift`
- `AeroshotTests/EditorProjectBridgeTests.swift`
- `_bmad-output/evolution/test-reports/WP-03-annotation-persistence.md`

Do not edit annotation model/renderer, editor canvas/window, package store/migrator, recording, themes, or project.pbxproj.

## Required implementation

- Backward-compatible optional/defaulted schema for stroke opacity, dash/phase/cap/shadow, fill opacity/corner radius, arrow endpoints/dimensions/inset/curve, and typography/background/padding/line height.
- Exact bidirectional bridge mapping for every field with validation and finite-number/range handling.
- Existing version-1 projects decode to legacy appearance defaults; customized appearances round-trip exactly.
- Tests cover a maximally customized annotation of each relevant category plus legacy/default decoding and malformed-value rejection.

## Truth and gate

No inspector or UI claim. Gate: customized properties survive project reopen, default projects retain byte-equivalent rendering defaults, full tests/build pass.
