# WP-05 media core verification

Status: complete — 2026-07-10

## Implemented scope

- Exact normalized rational media time and ranges with Codable/Hashable/Comparable support and checked arithmetic.
- Immutable source asset references and non-destructive composition slices.
- Pure split, trim-to-range, and selected-range deletion operations. Selected deletion is deliberately limited to a range wholly contained by the first slice; all following content closes toward zero. Cross-slice/full ripple editing is rejected.
- Earliest-occurrence source-to-composition mapping and composition-to-source mapping with exact slice offsets.
- Exact frame-step calculation, bounded J/K/L rate intent (`-8x...8x`), and `HH:MM:SS:FF` non-drop-frame formatting.
- Timed overlay, normalized crop/canvas, mute/gain, thumbnail request, and waveform request value models.
- AVFoundation compilation into `AVMutableComposition`, including source duration and declared-track validation, video transform preservation, audio gain/mute mix creation, typed errors, and retained source-asset lifetime during track insertion.

## Automated evidence

- Focused `MediaTimelineTests`: pass (14 tests), including 100 deterministic generated edit sequences, multiple-edit reversibility, boundary/zero-duration behavior, Codable round trip, invalid model/media rejection, and a real PCM asset composition.
- The real-media compiler test verifies the input bytes are identical before and after compilation.
- Combined concurrent `MediaTimelineTests` + `MediaExportTests`: pass. This caught and fixed an AVFoundation lifetime defect by retaining each `AVURLAsset` while its tracks are inserted.
- Full `AeroshotTests` target: pass.
- Debug app build with signing disabled: pass.

Commands:

```text
xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests/MediaTimelineTests test CODE_SIGNING_ALLOWED=NO
xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests test CODE_SIGNING_ALLOWED=NO
xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

## Explicitly deferred NLE features

- Clip reordering and arbitrary/full ripple semantics
- Cross-slice selected-range deletion
- Freeze frames and speed/rate segments
- Multi-track arrangement and advanced audio mixing
- Thumbnail decoding and waveform generation (request models only)
- Polished studio/timeline UI
- Export integration or export-quality claims
