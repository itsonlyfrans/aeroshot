# WP-00 performance budgets and measurement protocol

**Status:** Provisional product contract; no application performance result is established by this document.
**Date:** 2026-07-10
**Applies to:** The first sellable vertical slice on macOS 14.6 and later.

## Gate policy

A target becomes a release gate only after the protocol below has been run on both:

1. a named oldest-supported Mac representative of the minimum shipping hardware; and
2. a named reference Mac used by the team for repeatable development measurements.

Every published result must include raw samples, fixture checksum, build revision, build configuration, machine model, CPU/GPU, memory, macOS and Xcode versions, display resolution/scale/color space, cold or warm state, background load, power source, thermal state, sample count, and percentile method. A missing field invalidates the result. Changing a target requires an evidence-backed product tradeoff recorded beside the result; a budget must not silently move to make a build pass.

## Provisional budgets

| Area | Provisional release target | Required population / fixture |
|---|---|---|
| Warm capture command to interactive selection HUD | p95 <= 200 ms | 30 warm samples per capture mode on the single-display still fixture |
| Selection commit to visible thumbnail | p95 <= 500 ms | 30 warm samples of a single-display still capture |
| Canvas interaction | p95 frame time <= 16.7 ms at 60 Hz; report p99 and hitch count over 33.4 ms | 60-second scripted pan/zoom/move run with 100 visible annotations |
| Autosave | Save is scheduled no later than 2 seconds after the last edit; main-thread stall <= 50 ms; atomic replacement succeeds | 30 edits against the autosave fixture plus fault injection |
| Recording health | Unintended dropped complete frames < 0.5% | 10-, 30-, and 60-minute A/V fixtures at every supported preset in the performance matrix |
| Audio/video synchronization | Absolute drift <= 50 ms | Start, midpoint, and end measurements for the 10-, 30-, and 60-minute A/V fixtures |
| GIF editing memory | Peak RSS <= the smaller of 2 GiB or 12.5% of physical memory; retained RSS 30 seconds after close <= launch baseline + 250 MiB; duration slope from 30 to 60 seconds <= 5 MiB/minute | 60-second 2560x1440, 15 fps GIF fixture, with a matched 30-second fixture |
| Export responsiveness | Progress appears within 500 ms; cancellation is acknowledged within 500 ms and completes within 2 seconds | MP4 and GIF export fixtures, 30 warm samples for progress/cancel latency |
| MP4 export throughput | Reference Mac p95 elapsed/media-duration ratio <= 1.0 for H.264; oldest-supported Mac p95 <= 2.0; report hardware/software encoder choice | 60-second 2560x1440 60 fps H.264 fixture with stereo audio and ten timed callouts, 10 samples |
| GIF export throughput | Reference Mac p95 elapsed/media-duration ratio <= 2.0; oldest-supported Mac p95 <= 4.0 | 15-second 1440p 15 fps fixture with crop, timing changes, and ten callouts, 10 samples |
| Recovery | Every injected interruption leaves the previous valid project or a discoverable recoverable session | Failure matrix covering process kill, disk full, write denial, corrupt generated data, and interrupted export |
| Project package integrity | Originals remain immutable; interrupted manifest/asset writes never replace the last valid generation | Checksum assertions before/after each recovery fixture |
| Color fidelity | Source profile is preserved or conversion is explicit; preview/export delta is reported | Matched sRGB and Display P3 still/video fixtures with color-patch delta measurement |
| Generated cache | Cache is bounded by the configured limit, purgeable, and reproducible; no original is evicted | Projects at 0.5x, 1x, and 2x the configured cache limit |
| Privacy events | Keystrokes/event tracks are off by default, inspectable, deletable, and absent from diagnostics | Opt-in/out project fixtures plus redacted diagnostic bundle inspection |
| Reliability | >= 99.5% crash-free beta sessions before release candidate | Consented aggregate beta telemetry; local development runs do not qualify |
| Accessibility | All three golden workflows complete keyboard-only and expose meaningful VoiceOver names, values, and actions | Manual keyboard and VoiceOver scripts in light/dark, increased contrast, and reduced motion |

The memory and throughput values are initial product targets, not claims about the current implementation. Revalidate them after the first valid baseline on the oldest-supported machine.

## Canonical fixtures

Fixture files must be generated deterministically, checked into the future performance corpus or stored with immutable checksums, and contain no personal or captured user content.

| ID | Definition |
|---|---|
| `still-single-display-v1` | 3456x2234 Display P3 synthetic desktop, one 1440x900-point selection at 2x scale, opaque and alpha regions, no private content |
| `canvas-100-v1` | The still fixture with exactly 100 visible mixed annotations, including text, arrows, steps, shapes, blur, and solid redactions |
| `autosave-v1` | Project containing the still source, 100 annotations, a 10 MiB deterministic auxiliary asset, and an existing valid prior generation |
| `av-1440p60-v1` | 2560x1440 60 fps color bars/motion grid with frame numbers and stereo impulse markers at known rational timestamps; 10-, 30-, and 60-minute variants |
| `gif-1440p15-v1` | 2560x1440 15 fps deterministic motion grid; matched 30- and 60-second variants |
| `mp4-export-v1` | 60-second `av-1440p60-v1` project with ten timed callouts, one crop, stereo audio, and an H.264 1440p60 preset |
| `gif-export-v1` | 15-second GIF project at 1440p15 with crop, ten timed callouts, variable timing, and explicit loop count |
| `color-patches-v1` | Numerically defined sRGB and Display P3 patch sets embedded with their source profiles |

Fixture manifests must include SHA-256 checksums, byte sizes, dimensions, frame rate/timebase, duration, color profile, audio format, and project schema version.

## Common run protocol

1. Record the repository revision and whether the working copy is dirty. Use a Release build with signing disabled unless the metric explicitly evaluates Debug behavior. Never mix configurations in one sample set.
2. Record hardware and software with `system_profiler SPHardwareDataType SPDisplaysDataType`, `sw_vers`, `xcodebuild -version`, and an in-app diagnostics export that excludes file paths and captured content.
3. Connect AC power, disable Low Power Mode, fix the display configuration, and record the effective point size, pixel size, backing scale, refresh rate, and color-space name. Leave display brightness fixed.
4. Before each set, record thermal state and the five highest CPU consumers. Abort and repeat the set if thermal state is serious/critical, a system update/indexer is active, or another process sustains more than 10% CPU during a sample.
5. A **process-cold** sample starts after terminating Aeroshot and waiting until it has no process. A **warm** sample follows one unrecorded complete workflow in the same app process. OS disk-cache state is not called cold unless the runner can prove and record it; otherwise label it `UNCONTROLLED`.
6. Use signposts based on `ContinuousClock`/mach continuous time for product events. Capture frame pacing, main-thread stalls, RSS, CPU, energy, and encoder activity with Instruments or `xctrace`. Do not infer product latency from `xcodebuild` wall time.
7. Run latency/frame/memory sets at least 30 times unless the budget specifies a long-duration sample count. Alternate fixture order where variants are compared. Keep failed attempts in the raw log with a reason; do not discard outliers silently.
8. Compute percentiles with the nearest-rank method: sort `n` samples ascending and select rank `ceil(p * n)`. Report min, median, p95, p99 when `n >= 100`, maximum, and every raw sample. Ratios and drift use unrounded source values; round only presentation values.
9. Save an Instruments trace or machine-readable log, fixture manifest, console excerpt with content redacted, and a Markdown summary for every run. A summary without its raw artifact is informational only.
10. Repeat the full matrix after any capture, render, persistence, timeline, GIF spool, or export-pipeline change. Compare identical fixtures and configurations.

## Metric event definitions

### Capture latency

- `capture-command`: receipt of the resolved menu/hotkey action on the app event loop, after macOS has delivered it.
- `selection-hud-interactive`: overlay is visible on all intended displays, input monitor is installed, cursor mode is applied, and the first selection event can be handled.
- `selection-commit`: mouse-up/keyboard confirmation accepted by the selection controller.
- `thumbnail-visible`: thumbnail window has committed its first non-empty frame and is accepting actions.
- Measure both process-cold and warm sets for area, window, display, and scrolling entry. The provisional p95 budgets above apply to the warm, single-display still path; publish other modes separately.

### Canvas and autosave

- Replay a deterministic 60-second input script over `canvas-100-v1`: continuous pan, zoom, selection changes, 20 drags, 20 resizes, and 20 inspector edits.
- Measure presentation frame intervals, dropped/hitched frames, event-to-presentation latency, CPU, energy, and peak/retained RSS. Use the active display refresh rate but normalize the gate to 60 Hz.
- For autosave, signpost last edit, scheduled save, serialization end, fsync/replace end, and main-thread intervals. Verify the prior generation after killing the process at each write boundary.

### Recording, memory, and sync

- Feed deterministic timestamps from the A/V fixture or a controlled virtual source; capture source, received, encoded, and written frame counts. A user pause, an intentionally filtered incomplete frame, and an explicitly configured lower output rate are not unintended drops and must be itemized separately.
- Determine A/V drift from known impulse/frame-marker pairs using rational media timestamps at start, midpoint, and end. Wall-clock observation is invalid.
- For GIF memory, sample physical footprint/RSS once per second from launch baseline through import, playback, editing, export, project close, and a 30-second quiescence period. Fit a least-squares slope over steady-state 30- and 60-second fixtures and publish raw samples. Memory pressure, swap, and temporary-file bytes are separate reported series.

### Export, recovery, color, and cache

- Start time is acceptance of a validated export request; progress time is first user-visible determinate or explicitly indeterminate progress; completion requires a closed, probe-readable output file. Record elapsed time, media-duration ratio, output bytes, CPU/energy, encoder identifier, and fallback reason.
- Trigger cancellation at 10%, 50%, and 90% progress. Verify prompt UI acknowledgement, bounded worker shutdown, deletion or explicit recovery of partial output, and preservation of the project.
- Run recovery fault injection at every atomic-write boundary. Compare immutable-original SHA-256 values and validate the prior manifest before accepting recovery.
- Decode `color-patches-v1` through both preview and export paths. Record source/output ICC metadata, conversion intent, and numeric patch deltas; visual inspection alone is insufficient.
- Fill generated cache past its configured limit with deterministic proxies, thumbnails, waveforms, and GIF previews. Verify the bound after quiescence, explicit purge behavior, regeneration, and immutable-original preservation.

## Evidence-state vocabulary

- `MEASURED`: valid fixture, required environment metadata, raw samples, and protocol-compliant method are attached.
- `NOT MEASURED`: no valid protocol run exists; a target is only provisional.
- `INVALID`: data was collected but violates the protocol and cannot support a gate.
- `BLOCKED`: a named fixture, harness, machine, permission, or external evidence source prevents the run.

Build success, unit-test success, screenshots, design references, and subjective interaction impressions never promote an application performance metric to `MEASURED`.
