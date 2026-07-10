# Audit remediation plan

## Goal

Fix the confirmed privacy, output reliability, settings persistence, and verification defects identified in the UX/bug audit.

## Phase 1 — Independent product fixes

1. **Share Safe failure handling** — fail closed on scan errors and add regression coverage.
   - Gate: a scan failure never opens a share sheet with the original image.
2. **Output reliability** — reserve collision-free filenames and surface save errors instead of claiming success.
   - Gate: two captures in the same second receive different output paths; failed writes do not produce a success state.
3. **Settings integrity** — make reset/profile export/import include every applicable privacy setting and decode older profiles safely.
   - Gate: enhanced scan round-trips, reset clears it, and an older profile imports.

## Phase 2 — Test recovery and verification

1. Repair Swift 6 actor-isolation compile errors in the unit tests.
2. Add focused regression tests for Phase 1 fixes.
3. Run the unit suite and build.

Gate: `xcodebuild test` and `xcodebuild build` pass on macOS.
