# WP-07 — GIF core verification

Date: 2026-07-10

## Result

Gate passed. GIF capture no longer retains a duration-scaled `[CGImage]`. Capture frames are encoded directly into a bounded PNG spool, and export decodes/transforms one source frame at a time.

## Implementation evidence

- `GIFFrameSpool` enforces independent frame-count and byte-count ceilings, removes rejected overflow files, cleans owned storage on teardown, and recovers abandoned spool directories older than 24 hours.
- The spool's resident state contains only entry metadata. `Statistics.residentDecodedFrameCount` is structurally fixed at zero.
- `GIFDocument` uses exact integer-microsecond durations and supports frame-index and exact-time trim, split, delete, frame duplication/deletion, per-range duration changes, Codable round trips, loop once/count/forever, and ping-pong.
- `GIFWriter` supports resize, palette quantization, ordered dithering, transparency preservation or flattening, interpolation quality, adjacent duplicate-frame coalescing, cancellation-safe atomic destination replacement, deterministic size estimates, and effective export metadata.
- ImageIO frames include both `kCGImagePropertyGIFUnclampedDelayTime` and delay metadata, preserving sub-100 ms requested timing for capable readers.

## Deterministic fixture coverage

- 600 generated samples at 100 ms each exercise a 60-second-equivalent capture against a three-frame spool bound; only three small disk references remain and decoded-frame residency remains zero.
- Exact partial-frame timing edits and Codable round trip.
- Count/once/forever loop metadata and ping-pong model.
- Spool frame/byte bounds, overflow cleanup, explicit cleanup, and abandoned-spool recovery.
- Resize, palette, dither, quality path, transparency metadata, duplicate coalescing, unclamped 50 ms effective delay, cancellation, atomic destination preservation, and stable size estimate.

## Commands

```text
xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests/GIFStudioTests CODE_SIGNING_ALLOWED=NO
Result: TEST SUCCEEDED (8 tests)

xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests CODE_SIGNING_ALLOWED=NO
Result: TEST SUCCEEDED

xcodebuild build -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
Result: BUILD SUCCEEDED
```

## Explicit deferral

Changed-region/delta-rectangle optimization is deferred as allowed by WP-07. The current writer coalesces byte-identical adjacent frames and bounds memory, but writes complete output frames. No live-preview claim is made.
