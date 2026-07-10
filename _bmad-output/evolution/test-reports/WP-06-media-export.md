# WP-06 — Media export verification

Date: 2026-07-10

## Implemented

- Immutable `MediaExportSnapshot` captures the project ID, resolved immutable source asset, canvas, timeline, ordered overlays, and event tracks without retaining manifest/editor state.
- `MediaOverlayCompiler` is the shared value boundary for preview/export. Offline export converts those commands to Core Animation layers; blur/pixelate are rejected explicitly because Core Animation cannot reproduce those filters truthfully.
- H.264 and HEVC presets validate even dimensions, 16…8192 resolution, and 1…120 fps. Estimates use deterministic bits-per-pixel heuristics and disclose ±25% VBR/source-complexity uncertainty.
- Export normalizes to Rec.709 SDR, applies requested output size/frame duration, letterboxes the source transform, and renders supported overlays offline.
- `MediaExportCoordinator` is async and cancellable. It emits progress `0` before work, polls AVFoundation progress, exports to a sibling UUID partial, verifies the resulting codec, then atomically replaces/moves the destination. Cancellation/failure always removes the partial and preserves any existing destination.
- Encoder evidence is deliberately limited: the completed bitstream codec is verified, while hardware use and software fallback remain marked unobservable because `AVAssetExportSession` exposes neither fact.

## Automated evidence

- Application build: **PASS**
  - `xcodebuild -project Aeroshot.xcodeproj -scheme Aeroshot -configuration Debug -derivedDataPath /tmp/aeroshot-wp06 build CODE_SIGNING_ALLOWED=NO -quiet`
- Focused WP-06 suite: **PASS (4/4)**
  - deterministic snapshot/overlay ordering
  - deterministic preset validation/size estimate
  - generated AVAssetWriter fixture exported to a valid MP4 with verified H.264 bitstream and atomic destination replacement
  - cancellation preserved the existing destination and left no `.partial.mp4`
  - command: `xcodebuild test ... -only-testing:AeroshotTests/MediaExportTests`
- Integrated unit suite: **WP-06 tests pass; suite has one unrelated failure**
  - Both generated fixture and cancellation tests passed in the integrated run.
  - Existing concurrent WP-05 test `MediaTimelineTests.compilerBuildsRealCompositionWithoutMutatingSource()` failed.
- The generated runner issue was subsequently resolved by enabling Developer Mode and preserving signing; the full signed UI suite passed 6/6 through `scripts/run-ui-tests.sh`.

## Gate assessment

- Generated fixture export valid: **PASS**
- Cancellation and partial cleanup: **PASS**
- Prompt/testable progress and truthful result: **PASS**
- Preview/export snapshot identity: **PASS at the compilation boundary**; no Studio preview UI is claimed.
- Hardware/fallback evidence: **truthfully unavailable through AVAssetExportSession**; output codec itself is verified.

## Manual / hardware limitations

- No visual color-chart comparison was performed. Rec.709 metadata/policy is configured, but color fidelity still needs a controlled display/source comparison.
- No Intel, older Apple Silicon, HDR, or long-duration hardware matrix was available.
- Hardware encoder selection and fallback cannot be observed using this AVFoundation API; neither is claimed.
- Blur/pixelate offline overlays remain explicitly unsupported rather than silently diverging from preview.
