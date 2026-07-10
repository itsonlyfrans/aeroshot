# WP-08 controller — Local automation surfaces

## Mission

Expose consistent local project/export actions through URL schemes, Shortcuts/App Intents, AppleScript, and command-line launch arguments without weakening privacy or duplicating business logic.

## Allowed files

- `Aeroshot/Automation/**`
- `Aeroshot/App/AppDelegate.swift`
- `Aeroshot/Info.plist`
- `AeroshotTests/AutomationRouterTests.swift`
- `_bmad-output/evolution/test-reports/WP-08-automation.md`

Preserve all pre-existing AppDelegate/Info edits. Do not edit project schema/bridges, editor/Studio, recording, history, export internals, themes, project.pbxproj, or website.

## Required implementation

- One typed local action router for capture modes, open project, export preset, reveal, and privacy review; validate paths/URLs and never execute arbitrary shell input.
- Registered `aeroshot://` URL routes with percent-decoding/path safety.
- App Intents/Shortcuts for supported actions with meaningful entities/results and platform availability.
- AppleScript command classes plus scripting definition for the same bounded actions.
- Command-line launch arguments that map only to typed actions and provide deterministic exit/result reporting where host lifecycle permits.
- Tests for every parser/route, invalid input, unsupported actions, privacy/export preconditions, and no-network behavior.

## Truth and gate

No standalone binary target or cloud endpoint claim unless actually implemented. Gate: all surfaces share the router, invalid/destructive input fails safely, tests/build pass.
