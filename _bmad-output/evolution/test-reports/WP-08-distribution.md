# WP-08 distribution and operational readiness

## Implemented

- Safe dry-run release preparation with an explicit `--execute` boundary that
  performs unit tests and a local archive only.
- Read-only artifact verification for bundle identity/version, permission usage
  descriptions, Developer ID authority, hardened runtime, nested signatures,
  signed entitlements, and optional stapled-notarization/Gatekeeper validation.
- Build, contribution, security, privacy, distribution, and release-checklist
  documentation, including project portability and the source-available boundary.
- Default-off, separate analytics/crash consent with allowlisted content-free
  event redaction and deliberately no network sender.
- An entitlement boundary that cannot block capture, edit, export, open, or save.
- Unit coverage for consent defaults, redaction, event allowlisting, and core
  operation independence from entitlement state.

## Local evidence — 2026-07-10

- `zsh -n scripts/build-release.sh scripts/verify-release.sh`: pass.
- `scripts/build-release.sh`: pass; printed the expected three-step dry run and
  performed no build, signing, upload, notarization, or publication.
- `scripts/verify-release.sh`: pass in input-only mode; required tools, all three
  privacy descriptions, and configured version `1.0 (1)` were found.
- Swift compiled both operations-policy source files during the full test build.
- Focused `OperationsPolicyTests`: pass, 3/3 tests. The suite is explicitly
  `@MainActor` for Swift 6 XCTest isolation.
- Full `xcodebuild test ... CODE_SIGNING_ALLOWED=NO`: pass, including all WP-08
  policy tests and the complete application unit suite.
- Independent unsigned Release configuration build: pass. This validates release
  compilation without claiming a Developer ID signature or notarization.

## Credential-gated evidence

No Developer ID identity, exported release app, notarization Keychain profile,
or publication authority was supplied or used. Consequently Developer ID
signature verification, notarization submission/acceptance, stapling, Gatekeeper
assessment of the final artifact, update-feed mutation, and publication remain
release-operator gates. Run `scripts/verify-release.sh` on the exact exported app,
then set `AEROSHOT_REQUIRE_NOTARIZATION=1` after submission and stapling.
