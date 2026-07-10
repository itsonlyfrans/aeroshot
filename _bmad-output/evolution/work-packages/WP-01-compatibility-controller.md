# WP-01 controller — macOS media capability matrix

## Mission

Make the macOS 14.6 compatibility boundary executable and documented without changing capture/recording behavior.

## Allowed files

- `Aeroshot/Platform/**`
- `AeroshotTests/MediaCapabilityTests.swift`
- `_bmad-output/evolution/specs/WP-01-media-compatibility.md`
- `_bmad-output/evolution/test-reports/WP-01-media-compatibility.md`

Do not edit recording services/controllers, project kernel, themes, editor, or project.pbxproj.

## Required implementation

- Typed capability/availability adapter covering ScreenCaptureKit/AVFoundation features used or proposed by the plan, including `SCRecordingOutput` isolation.
- Deployment-safe availability checks with macOS 14.6 fallbacks and no accidental target increase.
- Tests for policy decisions independent of the host OS where possible.
- Matrix documenting minimum OS, fallback, current use, and whether the capability is required or optional.

## Truth and gate

Do not claim runtime recording integration; this package supplies the adapter and evidence only. Gate: project builds at the existing deployment target and policy tests pass.

## Validation

Run focused tests/build and report compiler/platform limitations honestly.
