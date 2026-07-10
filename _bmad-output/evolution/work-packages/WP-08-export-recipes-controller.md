# WP-08 controller — Export recipes and destinations

## Mission

Unify documentation/social/retina/downscaled export recipes and local destinations across still, MP4, and GIF outputs with privacy review, validation, clipboard/drag/Finder/share-sheet support, and user-owned endpoint boundaries.

## Allowed files

- `Aeroshot/Export/Recipes/**`
- `AeroshotTests/ExportRecipeTests.swift`
- `_bmad-output/evolution/test-reports/WP-08-export-recipes.md`

Do not edit existing image/media/GIF exporters, editor/Studio UI, project schema, recording, history, automation, themes, or project.pbxproj.

## Required implementation

- Codable recipes for documentation, social ratios, retina/downscaled assets, format/quality, naming, and privacy-review requirement.
- Validated compiler into existing still/media/GIF export inputs without parallel rendering logic.
- Destination abstraction for file/Finder, clipboard, drag, NSSharingService/share sheet, and explicitly configured user-owned endpoint request (no built-in upload/account).
- ShareSafe fail-closed precondition model and auditable result metadata; no captured content in logs.
- Tests for presets, dimensions/naming, privacy failure, destination availability, clipboard/share request metadata, endpoint validation, and offline behavior.

## Truth and gate

No hosted service claim. Gate: recipes compile deterministically and privacy/destination failures are explicit; tests/build pass.
