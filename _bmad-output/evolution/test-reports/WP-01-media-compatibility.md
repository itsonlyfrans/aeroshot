# WP-01 media compatibility report

## Scope

This package adds compatibility policy and compile-time isolation only. It does not integrate `SCRecordingOutput`, alter recording behavior, or claim recording runtime validation.

## Gate

The gate requires:

1. The project builds at the existing macOS 14.6 application target.
2. Host-independent policy tests pass.
3. `SCRecordingOutput` symbols compile only inside a macOS 15 availability boundary.

## Validation record

Validated on 2026-07-10 with Xcode 27 beta and the macOS 27 SDK:

- Focused command: `xcodebuild -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests/MediaCapabilityTests CODE_SIGNING_ALLOWED=NO test`
- Result: **passed**; 6/6 policy tests passed.
- Deployment evidence: the compiler and linker used `arm64-apple-macos14.6` for the application and test bundle.
- Availability evidence: `SCRecordingOutput`, its configuration, and stream add/remove calls compiled inside `@available(macOS 15.0, *)`; no deployment-target increase was made.
- Latest-source typecheck: `xcrun swiftc -typecheck -swift-version 6 -target arm64-apple-macos14.6 -sdk "$(xcrun --sdk macosx --show-sdk-path)" Aeroshot/Platform/MediaCapabilityPolicy.swift Aeroshot/Platform/ScreenCaptureRecordingOutputAdapter.swift` passed.
- A subsequent full-unit-suite attempt was interrupted by an actor-isolation compile error in concurrently added `Aeroshot/Project/AeroProjectAutosaveCoordinator.swift`. That file is outside WP-01 scope. No error or warning named a WP-01 source or test file.

## Gate status

**WP-01 gate passed at the focused validation snapshot.** The app, adapter, and focused tests built at macOS 14.6 and policy tests passed. Integrated-tree validation must be rerun after the separate project-kernel compilation error is resolved.

No runtime recording integration or recording-behavior claim is made.
