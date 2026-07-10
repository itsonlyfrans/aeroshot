# WP-09 — Golden corpus and performance/reliability evidence

Date: 2026-07-10

## Scope and truth boundary

This work adds an executable, generated release corpus and benchmarks. It does not edit product source. Timings are reference-machine evidence only; they are not claims about the oldest supported Mac.

Explicitly **unmeasured** in this harness:

- capture-HUD input-to-presentation latency (requires instrumented live capture),
- live audio/video synchronization and recording energy use (requires live capture plus media/energy instrumentation),
- oldest-supported-hardware latency, memory, throughput, and energy budgets (hardware was explicitly deferred),
- hardware encoder selection or software fallback (AVFoundation does not expose this through the exercised export API).

## Reference environment

- Machine: Apple M4 Max, 128 GiB RAM
- OS: macOS 27.0 (26A5378j)
- Xcode: 27.0 beta (27A5218g)
- Swift: Apple Swift 6.4 (`swiftlang-6.4.0.25.4`, `clang-2100.3.25.1`)
- Architecture: arm64
- Background caveat: interactive developer workstation; other Xcode/build activity was present. Results are regression evidence, not controlled-lab certification.

## Corpus

`ReleaseCorpus` rebuilds fixtures in a fresh temporary directory using fixed seed `0xa3e05a0720260710` and fixed model UUIDs:

- sRGB patch image at 2× and Display-P3 patch image at 1×,
- 3× tall scrolling-page image,
- short H.264 MP4 containing a deterministic silent AAC audio stream,
- three-frame GIF with 20/70/130 ms requested delays and loop count 4,
- corrupt PNG-like bytes and a truncated GIF,
- 100 mixed annotations,
- exact 10,000-slice long-timeline model.

Every executable run emits `WP09_CORPUS` with SHA-256 values for all generated files. Image/GIF/malformed fixtures are regenerated twice and required to be byte-identical. MP4 is validated semantically because AVAssetWriter may embed container metadata; its SHA-256 is still recorded per run but is not misrepresented as byte-stable.

## Measurements and percentile method

Benchmarks use `ContinuousClock`. `WP09_METRIC` output contains every raw sample and nearest-rank p50/p95 (`ceil(p × n)`, one-based). No values are hard-coded into this report.

Executable measurements:

| Metric | Samples | State |
|---|---:|---|
| Package validated round trip | 20 | warm filesystem/cache |
| Recovery from corrupt current manifest | 20 | warm filesystem/cache |
| Bounds + hit testing for 100 annotations | 50 | warm |
| CGContext rendering for 100 annotations | 30 | warm |
| Validation/duration algebra for 10,000 slices | 50 | warm |
| Bounded disk-spool append | 20 | first cold I/O, then warm |
| First export progress callback | 1 | cold generated source |

The export regression also requires first progress under the provisional 500 ms budget, terminal progress of 1, observable cancellation, no committed cancelled destination, and no unexplained encoder claim. Cache regressions require a six-frame decoded-preview limit, a bounded spool by count and bytes, and zero decoded frames retained by the spool.

## Raw results and verification status

The focused benchmark suite passed 7/7 on 2026-07-10. XCTest case durations were 0.782 s for corpus generation/validation, 0.035 s for package round-trip/recovery, 0.045 s for annotation geometry/render, 0.203 s for the 10,000-slice timeline, 0.331 s for bounded GIF spool/cache, 0.334 s for color metadata, and 0.481 s for export progress/cancellation. The executable continues to emit raw `WP09_METRIC` samples for machine-readable regression collection; these case durations are runner-level evidence and are not substituted for those per-operation percentiles.

Commands:

```sh
xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS' \
  -only-testing:AeroshotTests/PerformanceReleaseTests \
  test CODE_SIGNING_ALLOWED=NO

xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS' \
  -only-testing:AeroshotTests test CODE_SIGNING_ALLOWED=NO

xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

Gate status: passed on the reference machine. The focused performance suite passed 7/7, the complete unit suite passed, the signed UI suite passed 6/6, and the Release configuration build passed. Oldest-supported-hardware and live capture energy/latency measurements remain the explicitly approved hardware deferral.
