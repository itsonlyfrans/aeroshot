# WP-02 controller — Unified design system

## Mission

Consolidate AeroTheme and SettingsTheme behind one semantic token vocabulary while preserving current appearance and call sites.

## Allowed files

- `Aeroshot/DesignSystem/**`
- `Aeroshot/Utilities/AeroTheme.swift`
- `Aeroshot/Settings/Design/SettingsTheme.swift`
- `AeroshotTests/DesignSystemTests.swift`
- `_bmad-output/evolution/test-reports/WP-02-design-system.md`

Preserve all pre-existing user edits in the two theme files. Do not edit settings components, HUD/editor views, project kernel, recording, or project.pbxproj.

## Required implementation

- Semantic tokens for color/state, typography, spacing, radius, elevation/material intent, focus, motion, and control metrics.
- Compatibility facades so existing AeroTheme/SettingsTheme call sites compile unchanged or with minimal aliases.
- Shared primitives only where they can be real and reusable now: button style, inspector row, panel, empty state, progress, toast, and permission state. Do not add inert controls.
- Reduced Motion, Increased Contrast, Reduce Transparency, keyboard focus, and semantic state treatment in APIs.
- Deterministic tests for token invariants and accessibility fallbacks where possible.

## Truth and gate

Do not claim screenshot regression or VoiceOver approval without running it. Gate: current app builds/tests, compatibility facades retain current behavior, primitives expose accessible labels/actions and environment fallbacks.

## Validation

Run focused tests and the prescribed build. Report manual visual/accessibility items separately.
