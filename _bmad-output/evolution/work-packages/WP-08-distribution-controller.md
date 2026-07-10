# WP-08 controller — Distribution and operational readiness

## Mission

Make the approved paid-signed/source-available boundary operationally reproducible while keeping licensing, telemetry, and updates outside capture/render/project correctness.

## Allowed files

- `docs/BUILDING.md`
- `docs/CONTRIBUTING.md`
- `docs/SECURITY.md`
- `docs/PRIVACY.md`
- `docs/DISTRIBUTION.md`
- `docs/RELEASE_CHECKLIST.md`
- `scripts/build-release.sh`
- `scripts/verify-release.sh`
- `Aeroshot/Operations/**`
- `AeroshotTests/OperationsPolicyTests.swift`
- `_bmad-output/evolution/test-reports/WP-08-distribution.md`

Do not edit signing identities/secrets, project settings, app feature code, website, existing plans, or project.pbxproj.

## Required implementation

- Reproducible build/test/archive/sign/notarize/update documentation and scripts with secrets supplied only through environment/keychain.
- Contribution, security-reporting, privacy, entitlements/permissions, project portability, and source-available boundary documentation.
- Opt-in aggregate content-free telemetry/crash-consent policy model, default off, with redaction rules and no network sender unless explicitly configured later.
- Licensing/entitlement boundary protocol outside core features; no capture/edit/export lock in this package.
- Verification script checks archive identity/entitlements, hardened runtime, nested code signatures, privacy descriptions, version, and notarization inputs without publishing.
- Tests for telemetry default-off/redaction and entitlement independence.

## Truth and gate

Do not notarize/publish or invent credentials. Gate: clean documented build-to-verification path, scripts dry-run safely, tests/build pass; external notarization remains credential-gated evidence.
