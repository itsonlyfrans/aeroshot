# WP-09 controller — Golden corpus and performance/reliability budgets

## Mission

Turn the roadmap's provisional quality budgets into reproducible benchmark/corpus evidence on the reference machine without pretending it represents oldest-supported hardware.

## Allowed files

- `AeroshotTests/ReleaseHarness/**`
- `AeroshotTests/PerformanceReleaseTests.swift`
- `_bmad-output/evolution/test-reports/WP-09-performance.md`

Do not edit product source, project settings, UI tests, security/privacy code, scripts, or project.pbxproj.

## Required implementation

- Deterministic generated corpus for sRGB/Display-P3-like patches, scale factors, scrolling pages, annotations, MP4 with audio, GIF timing/loop, corrupt/truncated assets, and long timeline models.
- Measurable tests/benchmarks for package round trip/recovery, 100-annotation geometry/render, long timeline algebra, GIF bounded spool, export progress/cancel, cache bound, and color metadata preservation where APIs expose it.
- Record machine/toolchain, fixtures/checksums, sample counts, warm/cold state, percentile method, background caveats, and raw results.
- Release budgets remain reference evidence; clearly label capture HUD latency, live A/V sync/energy, and oldest-hardware items unmeasured if not validly instrumented.

## Truth and gate

No invented p95 or hardware claims. Gate: corpus deterministic, regressions executable, actual measurements recorded, full tests/build pass.
