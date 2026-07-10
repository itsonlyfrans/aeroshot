# WP-09 — Diagnostics and reliability evidence

## Release gate

- [x] Diagnostics consent defaults off with no implicit opt-in.
- [x] Events accept only fixed enums, allowlisted counters, and allowlisted flags.
- [x] Adversarial metadata sanitization drops pixels/data, OCR, event data, titles, filenames, paths, URLs, tokens, secrets, unknown keys, strings, and binary values.
- [x] Support bundles are explicit, atomic, local-only exports; there is no network sender.
- [x] Corrupt project manifests/assets fail closed and a corrupt current manifest can recover the last valid generation.
- [x] Interrupted project saves retain the previous valid manifest.
- [x] Missing media sources do not replace an existing export destination.
- [x] Interrupted/invalid GIF output does not replace an existing destination or retain partial files.
- [x] GIF spool byte exhaustion rejects the new frame without retaining overflow data.
- [x] Recording recovery discovery ignores corrupt entries and retains valid recoverable sessions.
- [x] Stale generated cache does not replace immutable original project data.
- [x] Automation rejects remote, relative, traversal, duplicate, and unknown inputs.
- [x] Library reconciliation removes duplicates deterministically and marks missing sources.
- [ ] Crash-free beta cohort metric — **external/unmeasured**. Requires a real, consented beta cohort and an approved measurement source; no crash-reporting service is claimed.

## Reliability checklist

- Run the focused `ReleaseReliabilityTests` suite.
- Run the complete unit-test target and a clean Debug build.
- Confirm support-bundle fixtures contain none of the adversarial sentinels.
- Confirm prior valid destinations/manifests remain byte-for-byte intact after injected interruption.
- Confirm no diagnostics network entitlement, endpoint, sender, or background upload was added.
- Record beta cohort size, observation window, app version, crash-free sessions/users definition, and evidence source before changing the external metric to measured.

## Evidence status

Automated local evidence is recorded by the commands and results appended during WP-09 verification. Real-cohort crash-free performance and oldest-supported-hardware reliability remain external evidence and must not be inferred from simulator or local test success.

## Verification — 2026-07-10

- Debug application build: **passed** (`xcodebuild … build`).
- Focused WP-09 suite: **passed, 10/10** (`xcodebuild … test -only-testing:AeroshotTests/ReleaseReliabilityTests -skip-testing:AeroshotUITests`).
- Complete unit target: its verification attempt was externally interrupted while a concurrent UI-runner verification rebuilt the same scheme. No WP-09 test failure was reported before interruption; the root controller owns the final serialized full-suite run.
- The generated runner issue was resolved by enabling Developer Mode and preserving code signing. The guarded signed UI suite subsequently passed 6/6 via `scripts/run-ui-tests.sh`.
