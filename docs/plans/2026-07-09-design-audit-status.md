# Design audit remediation status

## Phase 0 — Shared theme foundation

- [x] Added app-wide `AeroTheme` tokens.
- [x] Defined the violet `AccentColor` asset for light and dark appearances.
- [x] Re-exported shared accent and card radius values from `SettingsTheme`.
- [x] Gate: Debug build and `AeroshotTests` pass; asset and token wiring confirm the unified accent.

## Phase 1 — Critical

- [x] Replaced all four live borderless menus with indicator-hidden plain menus and hover states.
- [x] Removed the dead duplicate editor header and tool rail.
- [x] Differentiated instant HUD actions from persistent modes.
- [x] Changed full-screen recording to a display-shaped glyph.
- [x] Expanded the HUD panel and removed its duplicate AppKit shadow.
- [x] Gate: Debug build and `AeroshotTests` pass; static menu/shadow checks complete.

## Phase 2 — Refinement

- [x] Unified record-button state, hairlines, idle foregrounds, control sizing, and press feedback.
- [x] Added a center-pixel loupe marker.
- [x] Unified copy, recording, permission, beautify, and scrolling iconography.
- [x] Added selected traits and labels to icon-only editor/HUD controls.
- [ ] Gate: Debug build and `AeroshotTests` pass; dark Settings reviewed. HUD/editor/thumbnail light/dark and live VoiceOver checks remain manual.

## Phase 3 — Polish

- [x] Unified selection hints and pill drawing.
- [x] Added HUD mode motion, simplified selection indicators, and removed shortcut duplication.
- [x] Aligned thumbnail overflow typography.
- [x] Documented and applied the icon rendering policy; reassigned the History All icon.
- [x] Added two Settings type tokens and adopted them for drifting micro/small text.
- [x] Made HUD width content-driven for localization headroom.
- [ ] Gate: Debug build and `AeroshotTests` pass. Screen Recording permission is confirmed; full light/dark capture walkthrough remains manual.
