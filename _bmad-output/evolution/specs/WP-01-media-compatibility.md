# WP-01 — macOS media compatibility matrix

## Policy

Aeroshot keeps its application and test deployment target at macOS 14.6. A feature newer than that target must be optional, have an explicit fallback, and keep all newer framework symbols inside an `@available` adapter. The executable source of truth is `MediaCapabilityPolicy`; this document explains the product behavior represented by it.

`SCRecordingOutput` is not a recording dependency. `ScreenCaptureRecordingOutputAdapter` isolates its macOS 15 symbols, while `MediaCapabilityPolicy.recordingBackend()` continues to select `AVAssetWriter` unless a future, validated integration opts in explicitly.

## Matrix

| Capability | Framework | Minimum macOS | Current/planned use | Requirement | macOS 14.6 behavior |
|---|---|---:|---|---|---|
| `SCStream` screen frames | ScreenCaptureKit | 12.3 | Current video/GIF capture | Required | Native |
| `SCScreenshotManager` | ScreenCaptureKit | 14.0 | Current still capture | Required | Native |
| `captureResolution` | ScreenCaptureKit | 14.0 | Current best-resolution still capture | Required | Native |
| System audio stream output | ScreenCaptureKit | 13.0 | Current optional recording audio | Optional | Native |
| Microphone stream output | ScreenCaptureKit | 15.0 | Current optional recording audio | Optional | Disable microphone capture; preserve screen/system audio recording |
| Microphone device selection | ScreenCaptureKit | 15.0 | Planned recording preflight | Optional | Disable ScreenCaptureKit microphone capture; no device selector |
| HDR capture configuration | ScreenCaptureKit | 15.0 | Planned capability | Optional | Capture SDR |
| `SCRecordingOutput` | ScreenCaptureKit | 15.0 | Optional optimization only | Optional | Continue `SCStream` + `AVAssetWriter` |
| `AVAssetWriter` | AVFoundation | 10.7 | Current MP4 writer | Required | Native |
| `AVAssetReader` | AVFoundation | 10.7 | Planned sample-level export fallback | Required | Native |
| `AVMutableComposition` | AVFoundation | 10.7 | Planned trim/split/speed kernel | Required | Native |
| `AVVideoCompositionCoreAnimationTool` | AVFoundation | 10.7 | Planned offline overlays | Required | Native |
| `AVAssetExportSession` | AVFoundation | 10.7 | Planned standard export | Required | Native |

## Deployment rules

- Do not raise the target to adopt convenience APIs.
- New call sites query `MediaCapabilityPolicy` rather than repeating version literals.
- Framework symbols introduced after macOS 14.6 remain in availability-annotated adapters.
- A runtime being capable does not enable a new backend automatically. Recording-output adoption requires explicit opt-in plus parity, interruption, audio-sync, and long-duration validation.
- The compatibility policy does not replace runtime permission, hardware, codec, or encoder checks.

## Evidence basis

Minimum versions were verified against the selected Xcode SDK framework availability annotations. The current repository uses `SCScreenshotManager`, `SCStream`, system audio, best capture resolution, ScreenCaptureKit microphone capture behind a macOS 15 check, and `AVAssetWriter`. The remaining AVFoundation entries and HDR/device-selection entries are roadmap capabilities.
