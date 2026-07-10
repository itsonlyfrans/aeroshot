# WP-01 controller — Project kernel

## Mission

Implement the Phase 1 versioned local project foundation without changing current capture behavior. Source of truth: the approved combined product-evolution plan, WP-00 product contract, and target-architecture diagram.

## Allowed files

- `Aeroshot/Project/**`
- `AeroshotTests/AeroProjectTests.swift`
- `_bmad-output/evolution/test-reports/WP-01-project-kernel.md`

Do not edit `EditorDocument`, annotations, themes, recording, export, history, project.pbxproj, or another agent's files.

## Required implementation

- Codable versioned manifest and compatibility metadata.
- Stable IDs for immutable original assets, checksums, media metadata, canvas, overlays, timeline/event/export placeholders, generated-cache policy, and recovery generation.
- Rational media time representation that round-trips without floating-point time loss.
- Package store with safe relative paths, path traversal rejection, immutable-original enforcement, checksum validation, atomic replacement, and recoverable prior generation.
- Explicit schema migration entry point with current-version round trip and future-version rejection.
- Debounced autosave coordinator that is testable without waiting on wall-clock UI behavior.
- Tests for round trip, migration, unknown future schema, corrupt manifest, checksum mismatch, path traversal, atomic-save preservation, and recovery.

## Truth and gate

No fake media editor, cloud sync, or UI. A package API may be real while EditorDocument integration remains pending. Gate: deterministic tests pass and original assets cannot be silently overwritten.

## Validation

Run the prescribed AeroshotTests command. Report exact results and deferred integration.
