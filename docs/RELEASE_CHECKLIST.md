# Release checklist

- [ ] Working copy and version/build numbers reviewed
- [x] Unit suite passes; signed UI suite passes
- [x] Privacy permission descriptions match behavior
- [x] `build-release.sh` dry run reviewed, then archive created
- [ ] Archive/export made with approved Developer ID identity and hardened runtime
- [ ] `verify-release.sh` passes on the exact exported app
- [ ] All nested code signatures and entitlements reviewed
- [ ] Notarization submitted with a Keychain profile and accepted; ticket stapled
- [ ] Gatekeeper assessment passes on a clean macOS account/machine
- [ ] Capture, edit, save/open project, and export smoke tests pass offline
- [ ] Analytics and crash consent remain off on first launch
- [ ] Release notes contain no private data; update feed reviewed separately
- [ ] Final artifact checksum recorded, then human-approved publication performed

## Local evidence — 2026-08-14

- Unit tests: 504 passed in 57 suites.
- Signed UI tests: 15 passed with zero failures. Four visual rows skipped because approved baselines are unavailable.
- Status item: the one-click action test passed from another foreground app.
- Website, XML, plist, shell, and diff checks passed.
- Archive: `/private/tmp/aeroshot-release-019ff8b3/Aeroshot.xcarchive`.
- Archive preflight: bundle, version, privacy text, nested signatures, entitlements, and hardened runtime passed.
- Executable: universal `x86_64 arm64`.
- Executable SHA-256: `86a820ceccb4b6ee1f42367006f19610b62ddac82cf9e848c935369c3b81a89b`.
- Signing state: Apple Development local archive. This archive is not a Developer ID export.

## Open release gates

- Approve visual baselines and run the complete visual matrix.
- Complete manual keyboard and VoiceOver checks on a signed installed build.
- Run the oldest-supported hardware and long-duration media matrices.
- Approve license and pricing terms.
- Export with the approved Developer ID identity.
- Complete notarization, stapling, Gatekeeper, clean-account, update, and offline checks.
- Approve the final artifact before publication.
