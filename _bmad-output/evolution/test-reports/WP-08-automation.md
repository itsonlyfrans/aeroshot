# WP-08 — Local automation controller

## Implemented

- A single typed `AutomationRouter` accepts capture, project-open, export-preset, reveal, and privacy-review actions.
- URL and launch-argument parsers accept only allowlisted actions and absolute local file URLs. Unknown fields, duplicate values, remote URLs, credentials, ports, and arbitrary commands fail closed.
- `aeroshot://` is registered and routed through the shared router.
- App Intents and AppleScript commands call the same router and return human-readable results.
- Launch arguments use `--aeroshot-action` and write deterministic result text to stdout/stderr while the app lifecycle remains active.
- Export requests enforce local project/destination preconditions and honestly reject unattended export because no supported headless Studio export session currently exists.
- No network or arbitrary shell execution exists in the automation implementation.

## Manual registration gates

- AppleScript must be verified in a signed installed application because Launch Services registers the scripting definition from the built bundle.
- App Shortcuts discovery must be verified from the signed installed build in Shortcuts; source/build validation cannot force the system registration database to refresh.

## Validation

- `xcodebuild build -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` passed.
- Focused `AutomationRouterTests` passed 4/4: every URL route, every launch-argument route, invalid/remote/duplicate/arbitrary-command rejection, shared-router dispatch, export precondition behavior, and the no-network assertion.
- App Intents metadata export passes with the application-wide shortcut count kept within Apple's limit of ten; Privacy Review remains a discoverable App Intent.
- The complete `AeroshotTests` unit target passes in the integrated tree. The UI-runner host issue was resolved by enabling Developer Mode and rebuilding with signing enabled; the guarded focused UI smoke test passes 1/1 in 2.523 seconds. See `WP-09-ui-runner.md` and use `scripts/run-ui-tests.sh` instead of disabling signing for the full scheme.
