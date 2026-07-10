# Aeroshot product evolution plans - 2026-07-10

This file consolidates the Aeroshot planning artifacts created or updated today for the product-evolution goal.

## Contents

1. Product evolution plan
2. Luna review brief
3. Luna review record

---

# Plan: Aeroshot product evolution

**Goal:** Evolve Aeroshot from a capable capture utility into a polished, commercially credible macOS screenshot, recording, GIF, and annotation studio without losing its fast native workflow.
**Date:** 2026-07-10
**Spec / context link:** Current task, repository audit, and official competitor product pages

**Luna review handoff:** `docs/plans/2026-07-10-luna-review-brief.md`

## Executive direction

Aeroshot does not need a ground-up rewrite. It already has the difficult platform foundations: ScreenCaptureKit image/video/GIF capture, scrolling capture, system and microphone audio, click highlights, webcam overlay, OCR, privacy redaction, history, pinning, beautification, and a non-destructive screenshot editor.

The product gap is coherence and depth:

- Video and GIF capture currently terminate as exported files rather than entering an editing workflow.
- GIF recording retains full in-memory frames and writes a fixed-delay infinite-loop GIF; there is no frame editor or optimization pipeline.
- The annotation object has only kind, points, color, width, text, font size, step number, and fill. Arrowhead geometry, dashes, opacity, typography, shadows, z-order, and temporal ranges do not exist in the model.
- Selection already supports moving and deleting one annotation, but there is no full transform system for resize, rotate, multi-select, alignment, or snapping.
- `AeroTheme` is a small token set while Settings has a separate design vocabulary. The product needs one design system and one interaction grammar across capture, editor, history, recording HUD, and onboarding.

The recommended product shape is a **fast capture utility with an optional studio**, not a general-purpose video editor. Capture should remain one gesture; deeper editing should appear only after the user chooses Edit.

The first commercially credible milestone is a vertical slice: instant capture, precise editable annotation, trustworthy recording with pause/recovery, basic trim and timed callouts, and reliable MP4/GIF export. Advanced transforms, timeline effects, library organization, automation, and commercialization infrastructure follow only after this slice meets its quality budgets.

## Current-state evidence audit

This matrix describes the current working copy, not intended behavior.

| Capability | Status | Authoritative repository evidence | Consequence |
|---|---|---|---|
| Still capture and scrolling capture | Implemented | `Capture/`, `Scrolling/ScrollingCaptureController.swift`, and `Scrolling/ImageStitcher.swift`; stitcher regressions exist in `AeroshotTests.swift` | Preserve these workflows and their coordinate/stitching tests |
| MP4 recording | Implemented, output-only | `RecordingController.swift:71-120` configures ScreenCaptureKit and starts `ScreenRecordingService`; stop writes a file at lines 137-173 | Build session controls and project handoff; do not reimplement basic capture |
| Audio, click, and webcam recording options | Implemented at capture time | `RecordingController.swift:85-116` starts click/webcam overlays and selects system/microphone audio | Move presentation effects toward editable metadata while preserving baked compatibility |
| GIF recording | Implemented with hard limits | `GIFRecordingService.swift:15-23` stores full `CGImage` frames in memory; lines 89-94 force infinite looping and one fixed delay | Replace duration-scaled memory and add editable timing/loop/optimization |
| Annotation tools | Implemented, shallow appearance model | `Annotation.swift:3-36` defines 11 tools but only points, color, width, text, font size, step, and fill | Introduce typed geometry and appearance before adding inspector controls |
| Arrow rendering | Implemented with fixed derived geometry | `AnnotationRenderer.swift:137-150` derives one head length and angle from stroke width | Arrowhead controls require schema, renderer, inspector, project, and migration work together |
| Selection and movement | Partially implemented | `EditorCanvasView.swift:147-157` selects; lines 202-210 move; lines 287-293 delete | Extend the existing command path with handles, multi-selection, transforms, and precise hit testing |
| Undo/redo | Implemented for current document commands | `AeroshotTests.swift:224-270` covers add, crop, beautify, modify, and redo invalidation | Generalize commands to the project kernel and add property/transform/timeline coverage |
| Editable project persistence | Missing | No `AeroProject`, document package, schema version, or migration symbols exist | This is the architectural prerequisite for media editing and commercial reliability |
| Video/GIF playback and timeline editing | Missing | No `AVPlayer`, `AVComposition`, `AVAssetReader`, timeline, trim, or time-range implementation exists | Build a focused media core before attempting polished timeline UI |
| Cross-surface design system | Partial | `AeroTheme.swift:4-27` has a small global token set; `SettingsTheme.swift:3-58` adds Settings-specific spacing, type, state, and motion | Consolidate semantics without discarding the stronger Settings work |
| Automated quality evidence | Strong for privacy/stitching/settings; weak for media | Current unit suite passes, but searches find no GIF or recording tests | Media implementation must start with deterministic recording/export fixtures |

### Verified baseline

- macOS deployment target: 14.6; Swift 6.
- `xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests test CODE_SIGNING_ALLOWED=NO` passes in the current working copy.
- The working copy already contains extensive user changes. Future implementation must preserve and build on them rather than reset or overwrite them.

## Competitive evidence

Official product material establishes the expected category baseline:

| Product | Evidence-backed strengths | Lesson for Aeroshot |
|---|---|---|
| [CleanShot X](https://cleanshot.com/) | Screenshot capture, scrolling capture, annotation, OCR, video and optimized GIF recording, cloud workflow, and a broad set of small workflow refinements | Category leaders win through end-to-end flow and accumulated details, not one flagship feature |
| [CleanShot X changelog](https://cleanshot.com/changelog) | Pause/resume recording, canvas zoom, editable screenshot project files, scrolling capture, and post-recording audio removal | Editable projects and safe post-capture correction are parity expectations |
| [Longshot](https://longshot.chitaner.com/blog/allfeatures/) | Screenshot capture, annotation, recording, pinning, OCR, measurement, color picking, quick actions, and settings | Measurement and utility tools can coexist if capture remains the organizing action |
| [Shottr](https://shottr.cc/) | Small native footprint, speed, scrolling capture, annotations, backgrounds, OCR-oriented pixel tools, and S3 upload | Native speed and precision are marketable differentiators; do not trade them for visual excess |
| [Screen Studio](https://screenstudio.net/en/) | Focused recording-to-polished-video workflow with automatic presentation effects | Recording polish comes from opinionated defaults and fast correction, not a full NLE interface |

Do not copy competitor layouts, icon arrangements, brand colors, or animation signatures. Adapt workflow principles and category expectations while retaining Aeroshot's own visual identity and privacy-first positioning.

## Platform feasibility evidence

- Apple’s [ScreenCaptureKit configuration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration) supports output dimensions, source/destination rectangles, cursor display, frame interval, queue depth, resolution, system audio, microphone capture, and microphone device selection. The plan’s recording preflight maps to platform capabilities rather than a new capture framework.
- Apple’s [ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) validates complete-frame filtering and warns that deeper frame queues consume more memory. Aeroshot already filters for complete frames; queue depth and memory must remain measured choices.
- [AVMutableComposition](https://developer.apple.com/documentation/avfoundation/avmutablecomposition) supports inserting, removing, and scaling media time ranges, which covers the proposed trim, split, ripple, and speed kernel.
- [AVVideoCompositionCoreAnimationTool](https://developer.apple.com/documentation/avfoundation/avvideocompositioncoreanimationtool) can place timed Core Animation overlays into offline exports. Apple separately notes that the animation tool is for offline rendering rather than `AVPlayer` preview, so Aeroshot needs one overlay model compiled to preview and export backends plus parity tests—not an assumption that one renderer instance serves both.
- [AVAssetReader](https://developer.apple.com/documentation/avfoundation/avassetreader) and [AVAssetWriter](https://developer.apple.com/documentation/avfoundation/avassetwriter) provide the sample-level path needed when composition/export presets are insufficient. Start with compositions and standard export; introduce sample-level rendering only for requirements proven to need it.
- Apple’s [GIF timing documentation](https://developer.apple.com/documentation/imageio/kcgimagepropertygifdelaytime) states that `kCGImagePropertyGIFDelayTime` is clamped to at least 100 ms and points to `kCGImagePropertyGIFUnclampedDelayTime`. Aeroshot currently uses the clamped key, so its GIF writer cannot faithfully express configured rates above 10 fps.
- `SCRecordingOutput` exists in current ScreenCaptureKit, but the app supports macOS 14.6. Phase 1 must record an API availability matrix before deciding whether it can replace any existing `AVAssetWriter` path; it is an optimization option, not a roadmap dependency.

## Provisional quality budgets

Phase 0 must measure each budget on named oldest-supported and reference hardware. Every result records fixture dimensions, display scale, color space, warm/cold state, sample count, percentile method, and background load. A target becomes a release gate only after baseline measurement; failures require an approved product tradeoff or a revised target with evidence.

| Budget | Initial target |
|---|---|
| Warm capture command to interactive selection HUD | p95 ≤ 200 ms |
| Selection commit to visible thumbnail | p95 ≤ 500 ms for a single-display still capture |
| Canvas interaction | p95 frame time ≤ 16.7 ms at 60 Hz with 100 visible annotations |
| Project autosave | Debounced ≤ 2 seconds after an edit; atomic write; no UI stall over 50 ms |
| Recording health | < 0.5% unintended dropped complete frames in the supported performance matrix |
| Audio/video synchronization | Absolute drift ≤ 50 ms at 10, 30, and 60 minutes |
| GIF editing memory | RSS does not grow linearly with recording duration; 60-second 1440p fixture stays below the Phase 0 hardware-specific ceiling |
| Export | Progress within 500 ms, cancellable throughout, no unexplained software-encoder fallback |
| Recovery | Every injected interruption leaves either a valid prior project or a discoverable recoverable session |
| Project package integrity | Original assets remain immutable; interrupted manifest/asset writes pass failure-injection recovery |
| Color fidelity | Source color profile is preserved or conversion is explicit; preview/export delta is measured |
| Generated cache | Proxies, thumbnails, waveforms, and GIF previews obey a bounded, purgeable cache budget |
| Privacy events | Keystroke/event tracks are opt-in, inspectable, deletable, and excluded from diagnostics |
| Reliability | ≥ 99.5% crash-free beta sessions before release candidate |
| Accessibility | All golden workflows complete keyboard-only and expose meaningful VoiceOver names, values, and actions |

## Product principles

1. **Instant first, deep on demand.** Capture, copy, save, or drag in one step; open Studio only for deliberate editing.
2. **One project model.** Images, videos, and GIFs share annotations, styles, undo, export presets, and project persistence.
3. **Direct manipulation plus precision.** Every draggable control has a numeric inspector equivalent; arrowhead size is the canonical example.
4. **Local-first and reversible.** Keep original media immutable, keep edits non-destructive, and make cloud/upload behavior explicit.
5. **Apple-like means behavioral quality.** Correct focus, keyboard access, menus, undo, accessibility, reduced motion, materials, and predictable window behavior matter more than imitating stock controls.
6. **Polish is systematic.** Tokens, components, transitions, error states, empty states, and export feedback are designed once and reused.
7. **Performance is a feature.** Capture startup, editor interaction, memory use, export time, and output size have measurable budgets.

## Release milestones

**Milestone A — Capture and annotate:** Preserve instant capture; add the project package, recovery, precise selection/resize, arrowhead controls, selection-aware inspector, and polished export.

**Milestone B — Record and correct:** Add recording preflight, pause/resume, A/V sync, interruption recovery, playback, trim, range deletion, timed callouts, and MP4/GIF export.

**Milestone C — Professional depth:** Add advanced transforms, styles, speed/freeze effects, GIF optimization, project library, automation, and distribution tooling.

No feature assigned to Milestone C may delay the Milestone B beta unless it closes a demonstrated data-loss, accessibility, privacy, or export-correctness defect.

## Feature tiers

### Release-critical parity

- Reliable area, window, display, scrolling, video, and GIF capture
- Countdown, pause/resume, cancel/recover, cursor visibility, microphone and system-audio controls
- Editable annotations with move/resize, undo/redo, crop, blur/pixelate/solid redaction, text, steps, and shapes
- Video/GIF trim, crop, playback, export presets, and size estimation
- Project save/reopen with autosave and versioned migration
- Keyboard navigation, VoiceOver labels, reduced motion, light/dark appearance, and clear permission recovery

### Professional depth

- Arrow start/end styles and independently adjustable arrowhead length, width, inset, and direction
- Stroke width, dash pattern, opacity, corner radius, fill opacity, shadow, typography, alignment, and reusable styles
- Multi-select, transform handles, snapping, alignment guides, z-order/layers, duplicate, lock, group, and copy/paste styles
- Timeline split/trim, time-ranged annotations, freeze frames, speed segments, cursor emphasis, click emphasis, webcam layout, and audio controls
- GIF frame/range editing, variable timing, loop count, ping-pong, palette/dither controls, resize, and optimization preview
- Export presets for social/product documentation, drag-out, clipboard, Finder, share sheet, and user-owned endpoints

### Aeroshot differentiators

- ShareSafe review before export/share for images and media, with visible findings and fail-closed behavior
- Local-first capture history and editable project recovery
- A single annotation language across screenshots, scrolling captures, video, and GIF
- Documentation mode: automatic step numbering, consistent callout styles, optional OCR-aware redaction, and reusable export recipes
- Lightweight native speed with no mandatory account or upload

## Target architecture

Introduce a versioned `AeroProjectPackage` instead of extending the image-only `EditorDocument` indefinitely.

```text
AeroProjectPackage
├── manifest: schemaVersion, projectID, timestamps, compatibility
├── assets: stable IDs, immutable originals, checksums, media metadata
├── canvas: crop, background, aspect, color-space policy
├── overlays: typed geometry, appearance, transform, z-order, optional CMTimeRange
├── eventTracks: cursor, clicks, keystrokes, webcam presentation
├── timeline: non-destructive source ranges, trims, speed, freeze, audio state
├── exports: presets and last successful export metadata
├── generated: bounded thumbnails, waveforms, proxies, palette previews
└── recovery: atomic-save generation and recoverable-session references
```

Runtime player, canvas, selection, and undo state are not persisted as the project schema. Generated assets are disposable and reproducible. External assets require explicit bookmark/reference handling or are copied into the package. All media time uses rational `CMTime` values.

Recommended boundaries:

- `Project/`: Codable manifest schema, package asset store, migrations, autosave, recovery, external-reference policy, and document coordination
- `EditorCore/`: shared annotation geometry, transforms, selection, commands, snapping, and undo
- `ImageStudio/`: image canvas and beautification adapters
- `MediaStudio/`: player, timeline, clip operations, time-ranged overlays, audio state, and thumbnails/waveforms
- `Rendering/`: a shared render graph with image and timed-media backends
- `Export/`: preset model, validation, progress, cancellation, estimated size, and writers
- `DesignSystem/`: unified tokens and components for every surface

Use Core Graphics/Core Image for existing still rendering and AVFoundation/VideoToolbox for media composition and export. Adopt Metal only after profiling proves a render path misses its frame budget; do not make a renderer rewrite a prerequisite for the first media editor.

### Compatibility rule

The project schema is the source of truth. Preview and export may use different platform backends, but they must consume the same immutable render snapshot and pass golden-frame parity checks. Every API newer than macOS 14.6 must be isolated behind an availability adapter with a tested fallback or trigger an explicit minimum-OS decision.

## Scope

| In | Out |
|---|---|
| Native macOS capture, screenshot editing, recording editing, GIF editing, annotation depth, design system, project persistence, export, quality gates | Windows/mobile ports, collaborative cloud documents, livestreaming, multi-track general-purpose filmmaking, plugin marketplace, AI-generated video |
| Open-source and commercial packaging readiness | Final licensing or pricing decision before product-market evidence |

---

## Phase 0 — Product contract and review gate

**Goal:** Freeze the product promise, target workflows, visual direction, and measurable quality budgets before expanding implementation.

**Tasks:**

- [x] Write three golden workflows: instant screenshot, annotated documentation image, and recorded demo edited to video/GIF.
- [x] Adopt paid signed distribution with source available as the reversible initial boundary; keep licensing outside capture, project, rendering, and export cores.
- [x] Define provisional performance budgets and a measurement protocol. Oldest-hardware measurements are explicitly deferred without weakening later release gates.
- [x] Produce light/dark high-fidelity references for capture HUD, Studio, timeline, inspector, export sheet, and history.
- [x] Record the unverified model review and its accepted/rejected patches. On 2026-07-10 the product owner explicitly removed verified Luna identity as a blocking gate.
- [x] Convert accepted decisions into a short PRD and interaction specification.

**Gate:** Approved by the product owner on 2026-07-10 with the recommended defaults. The Luna identity requirement is non-blocking and oldest-hardware benchmarks are deferred to the continuous release harness. Phase 1 is authorized.

---

## Phase 1 — Shared design system and project kernel

**Goal:** Establish foundations that prevent the image, video, and GIF experiences from diverging.

**Tasks:**

- [ ] Consolidate `AeroTheme` and `SettingsTheme` into semantic tokens for color, type, spacing, radius, elevation, material, focus, motion, and control metrics.
- [ ] Build shared button, segmented control, inspector row, popover, panel, scrubber, empty state, progress, toast, and permission components.
- [ ] Add versioned `AeroProject`, source types, overlay schema, export preset schema, migrations, autosave, crash recovery, and atomic writes.
- [ ] Record a macOS 14.6 compatibility matrix for ScreenCaptureKit and AVFoundation features; isolate newer conveniences such as `SCRecordingOutput` behind availability adapters instead of raising the deployment target accidentally.
- [ ] Adapt `EditorDocument` behind the project model while preserving current screenshot behavior.
- [ ] Add fixture projects and round-trip/migration tests.
- [ ] Establish screenshot-based visual regression fixtures for light, dark, increased contrast, and reduced motion states.

**Gate:** Existing screenshot editing opens and exports through `AeroProject`; project round trips are lossless; design-system reference surfaces pass visual and accessibility review.

---

## Phase 2 — Professional still-image editor

**Goal:** Make annotations feel like editable objects rather than marks baked toward export.

**Tasks:**

- [ ] Replace bounding-box-only hit testing with tool-specific paths and handles.
- [ ] Implement the release-critical transform subset first: select, move, resize, z-order, precise inspector edits, and keyboard nudging. Defer rotate, multi-select, group, lock, and advanced alignment unless they are needed to satisfy Milestone B.
- [ ] Expand `Annotation` into typed geometry and appearance values, including independent arrow start/end styles, head length, head width, inset, curve, dash, opacity, shadow, fill opacity, and corner radius.
- [ ] Make the inspector selection-aware: edits update selected objects, mixed values are represented, and numeric fields coexist with sliders.
- [ ] Add text font, weight, alignment, background, padding, line height, and callout-tail controls.
- [ ] Add reusable styles/presets and preserve them across launches and project files.
- [ ] Upgrade crop to adjustable handles, aspect constraints, rotation/straighten, and explicit apply/cancel.
- [ ] Add annotation geometry, command, renderer parity, hit-testing, and project persistence tests.

**Gate:** The release-critical annotation subset—select, move, resize, text, shapes, steps, redaction, crop, and arrow start/end geometry—round-trips through a project and renders equivalently in preview/export. Rotate, multi-select, group, lock, advanced alignment, and reusable styles may move to Milestone C and must not block recording work.

---

## Phase 3 — Recording control and reliability

**Goal:** Turn current MP4/GIF capture services into a trustworthy recording session.

**Tasks:**

- [ ] Add a preflight panel for source, area/window/display, resolution, frame rate, cursor, microphone, system audio, webcam, and countdown.
- [ ] Implement pause/resume with timestamp correction so video and audio remain synchronized.
- [ ] Add microphone/system-audio meters, device selection, recording state in the menu bar, and configurable hotkeys.
- [ ] Make cursor, click, keystroke, and webcam effects captured as metadata where possible so Studio can modify them later.
- [ ] Define an effect-capture matrix for cursor samples, clicks, keystrokes, and webcam presentation: required permission, recorded event schema, privacy retention, editable preview behavior, export behavior, and baked fallback. Keystroke capture is opt-in, visibly indicated, and excludes secure-input contexts.
- [ ] Add disk-space checks, interruption recovery, partial-file cleanup, explicit failure states, and a recoverable session manifest.
- [ ] Replace automatic Finder reveal with a post-recording thumbnail offering Edit, Copy/Drag, Save, and Reveal.
- [ ] Add recording integration tests using deterministic sample buffers and sync/duration assertions.

**Gate:** Pause/resume, cancel, interruption, low-space, microphone denial, and multi-display coordinate cases are tested; a completed recording opens as an editable project without destructive transcoding.

---

## Phase 4 — Focused video Studio

**Goal:** Provide the corrections and presentation tools needed for polished product demos without becoming a general NLE.

**Tasks:**

- [ ] Build playback with frame stepping, J/K/L transport, timecode, zoom-to-fit, and thumbnail timeline.
- [ ] Implement trim, split, and selected-range deletion first. Defer clip reordering, full ripple semantics, freeze frame, and speed segments until the Milestone B workflow is reliable.
- [ ] Reuse the annotation inspector with time ranges, fade in/out, and keyframe-free entrance/exit presets.
- [ ] Add crop, canvas/background, output aspect, cursor emphasis, click emphasis, webcam layout, and optional automatic zoom regions.
- [ ] Add audio mute/gain/fades and waveform generation; keep advanced mixing out of scope initially.
- [ ] Add cancellable background export with progress, H.264/HEVC presets, resolution/frame-rate controls, file-size estimate, and hardware-encoder fallback visibility.
- [ ] Verify preview/export parity at representative Retina and ultrawide resolutions.

**Gate:** A user can record, remove mistakes, add timed callouts, adjust cursor/webcam presentation, and export a shareable MP4 without leaving Aeroshot; preview and export agree within defined tolerances.

---

## Phase 5 — GIF Studio and optimization

**Goal:** Make GIF a deliberate output workflow rather than a fixed-delay dump of captured frames.

**Tasks:**

- [ ] Replace the full-frame in-memory recording ceiling with a bounded temporary-frame or intermediate-video spool.
- [ ] Reuse the media timeline for trim/split, range deletion, speed, crop, scale, and timed annotations.
- [ ] Add frame/range duration, duplicate/delete, loop count, forever, once, and ping-pong controls.
- [ ] Use and test unclamped Image I/O frame delays when sub-100 ms timing is requested; report effective playback timing when a target decoder cannot honor it.
- [ ] Add palette size, dithering, transparency policy, duplicate-frame coalescing, changed-region optimization, and live size estimates.
- [ ] Provide social/documentation presets and side-by-side quality/size preview.
- [ ] Add deterministic GIF metadata, timing, loop, memory, and output-size regression tests.

**Gate:** A 60-second capture can be edited without retaining every full-resolution frame in memory; loop/timing controls survive project reopen; optimized export meets the agreed quality and size budgets.

---

## Phase 6 — Workflow, history, and distribution

**Goal:** Turn isolated captures into a dependable daily workflow and prepare both open-source and paid distribution paths.

**Tasks:**

- [ ] Evolve History into a local library of images, recordings, GIFs, and editable projects with search, tags, favorites, and recovery status.
- [ ] Add consistent copy, drag, share sheet, Finder, URL scheme, Shortcuts, AppleScript, and CLI actions around project/export presets.
- [ ] Add export recipes for documentation, social ratios, retina/downscaled assets, and privacy-reviewed sharing.
- [ ] Define telemetry as opt-in, aggregate, and privacy-preserving; ensure the app remains fully usable without it.
- [ ] Document build, contribution, security reporting, privacy, code signing, notarization, updates, entitlements, and release process.
- [ ] Make a business decision using evidence: support burden, conversion intent, signing/update cost, and differentiation. Keep licensing/product entitlements outside capture and rendering core modules.

**Gate:** A clean machine can install, onboard, capture, edit, export, recover, and update. The project format and local core remain portable. The chosen revenue boundary has documented customer evidence, license compatibility, signing/update costs, and a reproducible release process; monetization does not weaken privacy, accessibility, or project ownership.

---

## Phase 7 — Commercial hardening

**Goal:** Make quality measurable enough for an open-source launch or paid release.

**Tasks:**

- [ ] Add a golden capture/export corpus covering displays, color spaces, scale factors, scrolling pages, audio combinations, and corrupt media.
- [ ] Add performance benchmarks for capture latency, canvas interaction, long timelines, memory, CPU/energy, and export.
- [ ] Add UI automation for golden workflows and manual release checklists for Screen Recording, Accessibility, Microphone, and camera permissions.
- [ ] Complete VoiceOver, keyboard-only, reduced motion, increased contrast, localization expansion, and error-recovery audits.
- [ ] Add crash reporting only with explicit consent and redact paths/content from diagnostics.
- [ ] Run beta cohorts against task-success, time-to-output, crash-free sessions, export failure, and project recovery metrics.

**Gate:** All release-blocking tests pass, no acceptance workflow has a known data-loss path, performance budgets are met on the oldest supported hardware, and launch documentation is complete.

## Dependency and delegation map

The execution shape is mixed:

- Phase 0 precedes all implementation.
- Phase 1 precedes the deeper editor/media work.
- Phase 2 and Phase 3 can proceed in parallel once the project kernel and design system are stable.
- Phase 4 depends on Phase 3 metadata and Phase 2's overlay/inspector architecture.
- Phase 5 reuses Phase 4 timeline/rendering primitives.
- Phase 6 can begin in parallel after project persistence stabilizes.
- Phase 7 runs continuously but owns the final launch gate.

For implementation, use one controller plan and bounded agents for design-system components, project schema, annotation geometry, recording reliability, media timeline, exporters, and test harnesses. Each agent must receive exact files, input artifacts, an output contract, and explicit non-overlap constraints. Do not let agents independently invent duplicate project or design-system models.

Before implementation begins, add a scoped execution section to the repository's applicable `AGENTS.md` or a work-package-local agent brief. Generate each non-trivial implementation prompt through the `ass-master-prompt` protocol, including authoritative artifacts, allowed files, forbidden overlap, tests, phase gate, and no-fake-feature rules. Do not modify the existing website-specific `website/AGENTS.md` for app work.

## Implementation work packages

These are handoff-sized packages for future execution. A package is not complete until its gate evidence is attached.

| ID | Package | Primary outputs | Depends on | Gate evidence |
|---|---|---|---|---|
| WP-00 | Product contract | Golden workflows, PRD, visual references, approved budgets, Luna review record, first sellable milestone | None | Signed Phase 0 decisions |
| WP-01 | Project kernel | `AeroProjectPackage`, manifest, asset store, source/overlay schema, migrations, atomic autosave, recovery fixtures | WP-00 | Round-trip, migration, corruption, and recovery tests |
| WP-02 | Unified design system | Semantic tokens, shared primitives, state catalog, light/dark/accessibility fixtures | WP-00 | Visual regression and keyboard/VoiceOver review |
| WP-03 | Annotation engine | Typed geometry/appearance, transforms, selection model, snapping, commands, renderer parity | WP-01, WP-02 | Geometry/property tests plus golden still exports |
| WP-04 | Recording session | Preflight, state machine, pause/resume timestamps, devices/meters, manifests, interruptions | WP-01, WP-02 | Deterministic A/V sync and recovery matrix |
| WP-05 | Media core | Player coordinator, composition model, trim/split/speed operations, thumbnails, waveform | WP-01, WP-04 | Timeline algebra/property tests and playback fixtures |
| WP-06 | Video Studio | Timeline UI, timed overlays, presentation effects, audio controls, export presets | WP-03, WP-05 | Golden workflow UI test and preview/export parity |
| WP-07 | GIF Studio | Spool, frame/range timing, looping, palette/dither optimization, size estimator | WP-03, WP-05 | Timing/loop metadata, memory, quality, and size corpus |
| WP-08 | Library and distribution | Project-aware history, recipes, automation, release/update/licensing boundaries | WP-01 | Clean-machine install-to-update walkthrough |
| WP-09 | Release harness | Performance, energy, accessibility, permission, corruption, and beta release gates | All, continuous | Published release-candidate evidence report |

## Acceptance criteria

- [ ] Existing instant screenshot workflows do not gain an extra mandatory step.
- [ ] Screenshot, video, and GIF projects reopen with all edits still editable.
- [ ] Users can numerically and directly manipulate arrowhead size and other visible annotation properties.
- [ ] Users can pause/resume recording, trim mistakes, apply timed annotations, and export without another app.
- [ ] GIF timing, loop, dimensions, palette/quality, and output size are editable and previewable.
- [ ] Preview and export use the same project data and produce visually equivalent results.
- [ ] Capture and editing remain local-first; no account or cloud upload is required.
- [ ] Core workflows are fully keyboard accessible and VoiceOver understandable.
- [ ] The app meets explicit latency, memory, energy, stability, and recovery budgets.
- [ ] The repository can support either open-source distribution or a paid signed build without compromising project portability, privacy, accessibility, or export correctness.

## Validation commands

```text
xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests test CODE_SIGNING_ALLOWED=NO
xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

## First action

Start Phase 1 with the `AeroProject` schema and unified semantic tokens. Keep the current unit suite as the compatibility floor and add baseline instrumentation as each subsystem becomes measurable. Do not start timeline UI before the project schema and shared annotation appearance model are approved.


---

# Luna review brief: Aeroshot product evolution

## Required reviewer identity

Run this brief with the actual Luna model. At the top of the response, record:

- model name shown by the host;
- model/version identifier, if exposed;
- host/application;
- review date.

If the host cannot attest that the reviewer is Luna, stop and label the review **UNVERIFIED MODEL IDENTITY**.

## Objective

Critique and improve Aeroshot's roadmap for becoming a polished, commercially credible macOS screenshot, screen-recording, GIF-editing, and advanced-annotation product.

Primary artifact:

- `docs/plans/2026-07-10-aeroshot-product-evolution-plan.md`

## Current product facts

Treat these as repository-audited facts:

- Aeroshot is a Swift 6 macOS app with a macOS 14.6 deployment target.
- It already captures areas, windows, displays, scrolling content, MP4, and GIF.
- Recording already supports system audio, microphone audio, click highlighting, and a webcam overlay.
- It already has OCR, ShareSafe redaction, history, pinning, beautification, crop, undo/redo, and 11 annotation kinds.
- A selected annotation can be moved or deleted.
- It lacks an editable project format, video/GIF timeline, pause/resume, full annotation transforms, arrowhead controls, and media-specific automated tests.
- GIF capture currently retains full `CGImage` frames in memory, writes one fixed frame delay, and forces infinite looping.
- The global design token set is much smaller than the Settings-specific design system.

## Competitive references

Review current official material from:

- CleanShot X: <https://cleanshot.com/>
- CleanShot X changelog: <https://cleanshot.com/changelog>
- Longshot: <https://longshot.chitaner.com/blog/allfeatures/>
- Shottr: <https://shottr.cc/>
- Screen Studio: <https://screenstudio.net/en/>

Use other competitors only when they add a distinct workflow lesson. Prefer first-party product pages, documentation, changelogs, or help centers. Separate verified facts from inference.

## Review questions

1. Is “fast capture utility with an optional Studio” the right product shape? Identify a stronger alternative if not.
2. Which three workflows should define the first commercially credible release?
3. Which roadmap features are table stakes, which are differentiators, and which are distracting scope?
4. Does the proposed `AeroProject` model correctly unify still images, video, GIFs, annotations, and export presets?
5. What should be cut from the first two release milestones?
6. Which interaction details make premium Mac apps feel custom and Apple-quality without copying Apple or competitor trade dress?
7. What editor layout and progressive-disclosure model best supports novices and precision users?
8. Are the provisional latency, frame-time, sync, memory, recovery, reliability, and accessibility budgets credible?
9. What product, technical, privacy, licensing, or commercialization risks are missing?
10. What is the strongest defensible positioning for an open-source and/or paid Aeroshot?

## Required output

Return one structured review containing:

1. **Verdict** — proceed, revise, or reject the direction, with a short rationale.
2. **Top five corrections** — ordered by expected impact.
3. **Workflow recommendation** — three golden workflows with entry, critical path, exit, and recovery.
4. **Feature triage** — Keep now / Later / Remove.
5. **UX direction** — concrete layout, component, motion, inspector, and timeline principles.
6. **Architecture critique** — risks and changes to the project/render/media boundaries.
7. **Commercial critique** — audience, positioning, open-source/paid boundary, and evidence still needed.
8. **Scorecard** — 1–5 scores for usefulness, differentiation, feasibility, coherence, native Mac quality, accessibility, privacy, and release readiness.
9. **Plan patches** — exact replacement or insertion text for the primary plan.
10. **Evidence** — direct source links beside supported claims and an uncertainty list.

## Review constraints

- Do not assume missing functionality is absent until it is checked against the current facts above.
- Do not propose a general-purpose nonlinear video editor.
- Do not recommend a renderer rewrite, Metal adoption, cloud account, or AI feature without a measured requirement.
- Preserve local-first operation and instant capture paths.
- Treat model identity, competitor facts, and technical API claims as verifiable evidence, not implication.


---

# Luna review record: Aeroshot product evolution

**Date:** 2026-07-10
**Reviewer identity visible to task:** Codex agent based on GPT-5
**Model identity status:** UNVERIFIED MODEL IDENTITY
**Host:** Codex desktop
**Primary plan:** `docs/plans/2026-07-10-aeroshot-product-evolution-plan.md`
**Brief:** `docs/plans/2026-07-10-luna-review-brief.md`

## Result

The advertised `luna` subagent returned a useful critique, but it could not independently attest that it was the actual Luna model. Treat this as an unverified subagent review, not a verified Luna-model gate.

Verdict: revise, then proceed.

Core critique: the product direction is correct, but the first release plan was too broad. The first commercial milestone should be a vertical slice that proves capture, precise annotation, recording recovery, basic edit/correction, and MP4/GIF export before advanced library, automation, timeline, and commercialization depth.

## Accepted changes merged into the plan

- Added a first commercially credible vertical slice to the executive direction.
- Added Milestone A/B/C release framing so advanced features do not block the first recording/editing beta.
- Replaced the generic `AeroProject` diagram with an `AeroProjectPackage` model that includes manifest, immutable assets, checksums, generated caches, event tracks, and recovery state.
- Clarified that runtime editor/player/undo state is separate from persisted project schema.
- Tightened the provisional quality-budget preamble to require named hardware, fixtures, sample count, percentile method, display scale, color space, warm/cold state, and background load.
- Added quality budget rows for project package integrity, color fidelity, generated cache bounds, and privacy event handling.
- Changed Phase 2 to prioritize the release-critical annotation subset before advanced transforms.
- Added a recording effect-capture matrix for cursor, clicks, keystrokes, and webcam presentation.
- Narrowed Phase 4's initial media edit scope to trim, split, and selected-range deletion before advanced timeline semantics.
- Replaced the Phase 6 licensing gate with evidence-based release, portability, privacy, accessibility, and ownership requirements.

## Suggestions accepted as later work

- Rotate, multi-select, group, lock, advanced alignment, reusable styles.
- Speed segments, freeze frames, waveform UI, audio fades.
- Automatic zoom regions and advanced webcam choreography.
- GIF ping-pong, palette editor, and changed-region optimization preview.
- Search, tags, favorites, AppleScript, CLI, and custom endpoints.

## Suggestions not fully adopted

- The review suggested open-sourcing the capture/editor/rendering core and monetizing signed builds, updates, support, team policy tooling, and optional hosted sharing. The main plan keeps this as a recommended evaluation path rather than a fixed decision because the user has not chosen open source, paid, or hybrid distribution yet.
- The review cited several competitor pricing anchors. The main plan does not encode pricing because willingness-to-pay, support cost, licensing, and update infrastructure evidence is not yet available.

## Review uncertainties

- The review could not attest that it was produced by the actual Luna model.
- Customer interviews, task benchmarks, willingness-to-pay data, support-cost estimates, and license-governance review are still missing.
- Competitor support for independent arrowhead length/width was not verified; Aeroshot should treat that as a professional-depth opportunity rather than proven parity.
- Package/reference behavior still needs validation against sandboxing, moved external files, iCloud-style coordination, corrupt media, and disk exhaustion.
