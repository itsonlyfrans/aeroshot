# WP-09 controller — Golden workflow UI and accessibility harness

## Mission

Add signed macOS UI automation for the three approved golden workflows and explicit keyboard/accessibility/permission-state evidence.

## Allowed files

- `AeroshotUITests/**`
- `scripts/run-ui-tests.sh`
- `_bmad-output/evolution/test-reports/WP-09-ui-accessibility.md`

Do not edit product source, unit tests, project settings, security/privacy code, or project.pbxproj.

## Required implementation

- Stable UI tests for launch/onboarding permission recovery, instant screenshot path without mandatory Studio, screenshot project open/edit/save/export, and recording/GIF Studio entry using safe fixtures/launch arguments available in the app.
- Keyboard-only navigation assertions, focus/labels/values/actions for key controls, reduced-motion/increased-contrast launch environment, and meaningful disabled reasons.
- Runner script keeps signing enabled, verifies Developer Mode, supports filters/results, and never triggers the unsigned damaged-runner path.
- Permission matrix/manual checklist for Screen Recording, Accessibility, Microphone, and Camera when automation cannot grant them.

## Truth and gate

Skip with exact reason when real OS permission state blocks a path; do not fake completion. Gate: runner initializes, stable automated paths pass, manual permission/VoiceOver gaps explicit.
