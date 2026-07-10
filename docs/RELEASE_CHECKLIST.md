# Release checklist

- [ ] Working copy and version/build numbers reviewed
- [ ] Unit suite passes; signed UI suite passes
- [ ] Privacy permission descriptions match behavior
- [ ] `build-release.sh` dry run reviewed, then archive created
- [ ] Archive/export made with approved Developer ID identity and hardened runtime
- [ ] `verify-release.sh` passes on the exact exported app
- [ ] All nested code signatures and entitlements reviewed
- [ ] Notarization submitted with a Keychain profile and accepted; ticket stapled
- [ ] Gatekeeper assessment passes on a clean macOS account/machine
- [ ] Capture, edit, save/open project, and export smoke tests pass offline
- [ ] Analytics and crash consent remain off on first launch
- [ ] Release notes contain no private data; update feed reviewed separately
- [ ] Final artifact checksum recorded, then human-approved publication performed
