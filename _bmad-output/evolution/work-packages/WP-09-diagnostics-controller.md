# WP-09 controller — Consent, diagnostics, corruption, and recovery hardening

## Mission

Close release-critical privacy/reliability gaps with content-free opt-in diagnostics, redacted support bundles, and failure-injection coverage across project, recording, media export, GIF, library, and automation.

## Allowed files

- `Aeroshot/Diagnostics/**`
- `AeroshotTests/ReleaseReliabilityTests.swift`
- `docs/DIAGNOSTICS.md`
- `_bmad-output/evolution/test-reports/WP-09-diagnostics-reliability.md`

Do not edit existing feature implementations, operations policy, project settings, UI tests, scripts, or project.pbxproj.

## Required implementation

- Default-off consent store and diagnostic event/support-bundle sanitizer excluding pixels, OCR, event data, window titles, filenames, paths, URLs, tokens, and secrets.
- No network sender; export is explicit local support bundle only.
- Failure-injection/integration tests for corrupt manifests/assets, interrupted autosave/export/GIF, low space/recovery discovery, missing sources, stale generated cache, automation path rejection, and library reconciliation.
- Reliability release checklist with crash-free beta metric marked external/unmeasured until real cohort evidence exists.

## Truth and gate

No crash-reporting service claim. Gate: consent defaults off, sanitization tests adversarially pass, recovery paths retain prior valid data, full tests/build pass.
