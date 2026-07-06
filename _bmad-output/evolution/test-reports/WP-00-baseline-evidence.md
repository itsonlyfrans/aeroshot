# WP-00 baseline evidence report

**Run date:** 2026-07-10
**Evidence status:** PARTIAL
**Scope:** Environment inventory plus prescribed Aeroshot unit-test and build validation. No application performance fixture was run.

## What is actually evidenced

- The prescribed `AeroshotTests` invocation completed with exit code 0 on this working copy.
- The prescribed Aeroshot build invocation completed with exit code 0 on this working copy.
- External wall times were recorded for reproducibility only. They are Xcode command durations, not capture, editor, memory, autosave, recording, or export benchmarks.

## Environment

| Field | Observed value |
|---|---|
| Machine | MacBook Pro, model identifier `Mac16,5`, model number `Z1FS00078LL/A` |
| CPU/GPU | Apple M4 Max, 16 CPU cores (12 performance + 4 efficiency), 40 GPU cores |
| Architecture | arm64 |
| Memory | 128 GB (137,438,953,472 bytes) |
| macOS | 27.0, build `26A5378j` |
| Xcode | 27.0, build `27A5218g` |
| Display | Built-in Liquid Retina XDR, 3456x2234 physical pixels, effective 1728x1117 points, 2.0 backing scale, reported color-space name `Color LCD` |
| Display caveat | Refresh rate and ICC profile identifier were not captured; color behavior is therefore not measured |
| Power / thermal | Not recorded; results cannot support a performance gate |
| Working copy | Dirty with extensive pre-existing user changes; no reset, cleanup, signing change, or code edit was performed for this report |
| Timestamp of final environment sample | `2026-07-10T16:18:13Z` |

The session was an ordinary interactive desktop session, not an isolated benchmark environment. At the final environment sample, WindowServer, Spotlight metadata processes, Bloom, Codex, Helium, and AlDente were active; WindowServer and Spotlight showed material CPU use. Other agents were also operating in the shared working copy. DerivedData was not cleared. The test command's cache state was uncontrolled; the build ran immediately after the test and was an incremental/warm toolchain build.

## Validation commands and results

Timing used `/usr/bin/time -p` directly around each prescribed command.

### Unit tests

```sh
/usr/bin/time -p xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests test CODE_SIGNING_ALLOWED=NO
```

Result: **PASS**, exit code 0.

```text
real 9.48
user 6.70
sys  2.62
Xcode-reported test operation elapsed: 3.164 seconds
```

The output reported passing suites for image stitching, undo, selection cursor, PII detection, geometry conversions, ShareSafe behavior/performance naming, region frame streaming, and settings storage. `ShareSafePerformanceTests` is a suite name; this run did not provide a protocol-compliant product performance baseline.

Xcode warnings:

- The scheme reported an empty supported-platform list for its buildables.
- Both arm64 and x86_64 matched the generic macOS destination; Xcode selected the first match, arm64 `My Mac`.

These warnings did not fail the command, but explicit architecture/destination selection should be considered for a future reproducible benchmark runner.

### Build

```sh
/usr/bin/time -p xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

Result: **PASS**, exit code 0.

```text
real 2.92
user 2.95
sys  0.80
```

The same supported-platform and multiple-matching-destination warnings appeared. This was an incremental build after the test run and is not a clean-build benchmark.

## Application performance evidence

The protocol is defined in `../specs/WP-00-performance-budgets.md`. None of the following was measured with a valid fixture and required instrumentation in this run.

| Metric | Evidence state | Reason |
|---|---|---|
| Capture command to interactive HUD | **NOT MEASURED** | Aeroshot was not launched with capture signposts or a deterministic capture fixture |
| Selection commit to visible thumbnail | **NOT MEASURED** | No instrumented selection/thumbnail run |
| Editor/canvas frame time with 100 annotations | **NOT MEASURED** | No 100-annotation fixture or frame trace |
| Project autosave timing/main-thread stall | **NOT MEASURED** | Project package/autosave fixture and fault-injection harness do not yet exist |
| Recording dropped complete frames | **NOT MEASURED** | No deterministic recording source or frame accounting run |
| A/V synchronization drift | **NOT MEASURED** | No timestamped 10/30/60-minute A/V fixture |
| GIF editing peak/retained memory and duration slope | **NOT MEASURED** | No matched 30/60-second 1440p fixture or RSS trace |
| Export progress/cancellation latency | **NOT MEASURED** | No instrumented MP4/GIF export fixture |
| MP4 export throughput | **NOT MEASURED** | No canonical project export or encoder evidence |
| GIF export throughput | **NOT MEASURED** | No canonical project export |
| Recovery and package integrity | **NOT MEASURED** | No atomic project package or interruption matrix |
| Color fidelity | **NOT MEASURED** | No sRGB/Display P3 patch fixture or numeric preview/export comparison |
| Generated cache bound/purge | **NOT MEASURED** | No project cache implementation/fixture |
| Privacy event-track behavior | **NOT MEASURED** | No project event-track fixture or diagnostic bundle inspection |
| Crash-free beta sessions | **NOT MEASURED** | No consented beta population evidence |
| Keyboard-only and VoiceOver workflow completion | **NOT MEASURED** | No manual accessibility run was performed |

## Blockers and next evidence

1. The canonical synthetic fixture corpus and checksums do not yet exist.
2. Product signposts for capture, thumbnail, canvas, autosave, recording, and export boundaries are not attached to this report.
3. Project package, media Studio, GIF spool, cache, and their deterministic fault-injection harnesses are future implementation work.
4. No named oldest-supported Mac was available. This M4 Max machine can serve as a reference machine only after power, thermal, background-load, build configuration, and cache state are controlled.
5. No valid manual accessibility, color, recovery, permission, or privacy diagnostic inspection was run.

## Gate statement

The compatibility floor is currently green on this machine: the prescribed unit suite and build pass. The WP-00 performance gate remains **PARTIAL / OPEN** because every application performance and quality metric is `NOT MEASURED`, the oldest-supported hardware baseline is absent, and no fixture-backed raw traces exist. These results do not authorize Phase 1 by themselves.
