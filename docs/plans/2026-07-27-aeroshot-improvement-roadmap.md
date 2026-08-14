# Plan: Aeroshot improvement roadmap

**Goal:** Improve Aeroshot's trust, capture speed, editor correctness, annotation productivity, media workflows, UI accessibility, and release readiness without rewriting the native foundations that already work.

**Date:** 2026-07-27

**Status:** Local remediation complete. External hardware, accessibility, distribution, and approval gates remain open.

**Spec / context links:** `docs/plans/2026-07-10-aeroshot-product-evolution-plan.md`, `_bmad-output/evolution/WP-10-completion-audit.md`, `_bmad-output/evolution/specs/WP-00-performance-budgets.md`, `design-qa.md`

## Direction

Aeroshot no longer needs the foundation-heavy roadmap written on 2026-07-10. The project now has editable image/video/GIF projects, typed annotations, media timelines, recording recovery, bounded GIF storage, export pipelines, multi-selection, autosave, a shared design system, and a signed UI runner. Automation exists, but full coverage of the current surfaces remains unverified.

The next release should therefore follow this order:

1. Close trust and data-integrity gaps.
2. Measure and fix the capture/recording hot paths.
3. Make preview, persistence, undo, and export agree across editors.
4. Improve keyboard, VoiceOver, and direct-manipulation workflows.
5. Add professional editor depth only after the existing workflows meet their gates.

No ground-up rewrite is authorized by this plan.

## Priority policy

| Priority | Meaning |
|---|---|
| P0 | Can expose private content, lose work, report a failed artifact as successful, or publish a false product promise |
| P1 | Breaks a golden workflow, causes correctness drift, blocks accessibility, or has an evidenced performance/reliability risk |
| P2 | High-value professional productivity or workflow polish |
| P3 | Breadth, experimentation, and convenience that must not delay P0-P2 |

## Current truth

| Surface | Already real | Highest-value remaining gap |
|---|---|---|
| Capture and HUD | Reviewable area/window/display capture, recording preflight, multi-display selection, truthful post-capture thumbnail | Live latency and signed multi-display boundary behavior are not measured |
| Still editor | Typed annotations, accessible layer list, multi-select/marquee, crop/straighten, project save/autosave, bounded transactional undo/redo | Signed keyboard and VoiceOver workflow evidence remains open |
| Video Studio | Playback, trim/split/delete, crop, complete overlay commands, latest-wins project persistence, shared preview/export text rendering | Approved visual baselines and live long-duration media evidence remain open |
| GIF Studio | Disk spool, timeline edits, exact playback, crop, complete annotation commands, shared preview/export rendering, project persistence, export | Representative large live GIF fixtures and approved visual baselines remain open |
| Performance harness | Native signposts, bounded counters, deterministic corpus, synthetic benchmarks, failure injection, release reliability tests | Reference and oldest-supported hardware budgets remain unmeasured |
| UI and accessibility | Truthful onboarding, exact Settings search focus, numeric screenshot comparison, signed UI runner and partial automation | Approved baselines plus complete keyboard/VoiceOver and permission matrices remain open |
| Trust and distribution | Local-first privacy rules, Share Safe review boundary, truthful preview website, release scripts and checklists | License terms and public release artifacts are not approved |

Historical feature matrices remain evidence of their original phase. They must not be used as a current implementation inventory where they conflict with the completion audit or current code.

## Latest local verification — 2026-08-14

- The complete unsigned unit run passed 504 tests in 57 suites.
- The complete signed UI run passed 15 tests with zero failures. Four visual rows skipped because approved baselines are unavailable.
- The status-item regression test opened the popover from Finder and completed the Settings action with one click.
- XML, plist, shell, diff, and website build checks passed.
- The local universal Release archive passed signature, entitlement, privacy text, version, and hardened-runtime preflight.
- The archive uses Apple Development signing. Developer ID export, notarization, Gatekeeper, and publication remain open.
- The archived executable SHA-256 is `86a820ceccb4b6ee1f42367006f19610b62ddac82cf9e848c935369c3b81a89b`.

## Scope

| In | Out |
|---|---|
| Capture/recording correctness, local performance instrumentation, still/video/GIF editor coherence, annotations, undo, preview/export parity, HUD/thumbnail/onboarding/settings UX, accessibility, Share Safe, history startup, truthful website/release evidence | General-purpose NLE, cloud accounts or collaboration, plugin system, Windows/mobile ports, renderer rewrite, speculative AI features, new annotation kinds without workflow evidence |
| Existing AppKit, SwiftUI, Core Graphics, ImageIO, ScreenCaptureKit, AVFoundation, and current project schema/bridges | Metal or FFmpeg unless measurements prove native paths cannot meet an approved budget |

---

## Workstream A — Trust and correctness

**Outcome:** Aeroshot never silently shares matched private content, reports a failed recording as complete, or publishes a capability it does not ship.

### A1 — Share Safe review boundary (P0)

**Evidence:** `ShareSafeService.shareAction` returns `.shareOriginal` when matches exist and `redactBeforeSharing` is off. `shareSafe` then opens the original-image share sheet after a toast.

**Implemented:** A matched scan now returns `reviewRequired` when automatic redaction is off. The native review alert makes **Redact & Share** the Return-key default, marks **Share Original** as destructive, offers Cancel, and includes the match count in its accessibility text.

The capture settings now separate automatic capture-output redaction from per-share Share Safe review. Unit tests cover the six decision cases and rendered solid redactions. A signed UI test verifies the native review dialog and Cancel path.

**Tasks:**

- [x] Add a `reviewRequired` decision for successful scans with matches when automatic redaction is off.
- [x] Make **Redact & Share** the safe default; offer Cancel and an explicit **Share Original** confirmation.
- [x] Preserve the existing fail-closed behavior when scanning fails.
- [x] Clarify the Capture Settings copy so automatic redaction and per-share confirmation are distinct.
- [x] Cover `{scan failed, no match, match} × {automatic redaction on, off}` in unit and UI tests.

**Gate:** No original-image share sheet appears after a match without a deliberate confirmation in that share attempt; the redacted path passes only a derived image with `fileURL == nil` and obscures every detected rectangle; Cancel has no side effects; scan failure reaches neither confirmation nor sharing; VoiceOver announces the match count and safe default.

### A2 — Recording terminal errors (P0/P1)

**Evidence:** `ScreenRecordingService.stream(_:didStopWithError:)` and `GIFRecordingService.stream(_:didStopWithError:)` only log. The controller can remain in an active-looking state until the user stops it.

**Implemented:** Both services now deliver one unexpected-stop signal. `RecordingController` uses one terminal task and one recovery workspace for MP4 and GIF.

Quit now waits for finalization. Aeroshot cancels Quit when finalization fails and keeps the recovery artifact available.

**Tasks:**

- [x] Deliver the first terminal stream error to `RecordingController`.
- [x] Leave recording state within one second, stop timers/meters/overlays, and preserve the recovery policy.
- [x] Never present a partial destination as completed.
- [x] Make repeated Stop/Cancel/error callbacks idempotent.
- [x] Add deterministic stream-failure injection for video and GIF.

**Gate:** Every injected terminal error produces one truthful terminal UI state, no completed-file claim, and either a valid recovery entry or documented safe cleanup.

### A3 — Website and support truth (P0 before public release)

**Evidence:** `website/src/pages/index.astro` contains `href="#"` product/legal CTAs, advertises macOS 13 while the app target is 14.6, and describes capabilities that are not backed by a current app surface or test.

**Implemented:** The website now presents an honest development preview with no download or repository promise. Privacy and security pages expose the repository documents through generated Markdown routes.

Public feature statements now match shipping behavior. Concepts and illustrations are labelled. `docs/WEBSITE_CLAIMS.md` maps each feature statement to code and automated evidence.

**Tasks:**

- [x] Replace placeholder download, privacy, security, and repository destinations with real links or an honest preview/source-build state.
- [x] Make supported macOS copy match the Xcode deployment target.
- [x] Map every feature claim to a shipping surface and test/evidence file; remove or label concepts.
- [x] Keep `docs/PRIVACY.md` and `docs/SECURITY.md` reachable from the website.

**Gate:** No product/legal CTA uses `#`; download/legal/repository links resolve and point to the intended artifact or document; every public feature sentence has a current evidence mapping; the website build and keyboard/accessibility smoke pass.

---

## Workstream B — Performance and reliability

**Outcome:** Capture feels instant, recording remains bounded under backpressure, and optimization work is driven by reproducible measurements.

### B1 — Native measurement seams (P1)

**Files:** `AppState.swift`, `CaptureController.swift`, `AllInOneController.swift`, `FloatingThumbnailController.swift`, `ScreenRecordingService.swift`, `GIFRecordingService.swift`, `HistoryStore.swift`, `PerformanceReleaseTests.swift`

**Tasks:**

- [x] Add local `OSSignposter` intervals for app-ready, overlay-ready, selection commit, editor/thumbnail visible, writer queue wait, GIF spool append, and export.
- [x] Add lock-backed counters for arrived/appended/dropped samples, pending video/audio buffers, scratch bytes, and first terminal error.
- [x] Record raw samples and fixture/environment metadata defined by `WP-00-performance-budgets.md`; do not add network telemetry. The harness emits `NOT MEASURED` and `UNVERIFIED` for evidence fields that the runner does not supply.
- [ ] Turn stable same-runner benchmarks into regression gates only after an absolute budget passes.
- [ ] Measure `capture-command → selection-hud-interactive` over 30 warm samples per capture mode on `still-single-display-v1`; "interactive" includes visible overlays, installed event monitors, applied cursor mode, and input readiness.
- [ ] Approve a numeric preview/export pixel/color tolerance and dynamic-region mask policy before a parity test may claim pass; until then, report deltas and retain manual review.

**Gate:** Every claimed latency/queue/memory result has raw samples, revision, build configuration, hardware, display, thermal/background state, and percentile method; warm capture-to-HUD p95 is ≤ 200 ms.

**Current evidence state:** Instrumentation and content-free local counters are implemented and covered by the performance release suite. No protocol-valid reference-machine or oldest-supported-machine run is attached, so latency and queue budgets remain `NOT MEASURED` and are not release claims.

### B2 — Bound recorder backpressure (P1)

**Evidence:** Each complete media sample is retained by an asynchronous `writerQueue` closure before `AVAssetWriterInput.isReadyForMoreMediaData` is checked.

**Tasks:**

- [x] Enforce explicit pending limits, initially video ≤ 2 and each audio track ≤ 8.
- [x] Count intentional backpressure drops separately from incomplete or paused samples.
- [x] Rate-limit audio meter scans independently of audio writes.
- [x] Preserve rational timestamps and pause/resume correction.

**Gate:** The canonical 10/30/60-minute `av-1440p60-v1` matrix runs at every supported preset, with rational markers checked at start/midpoint/end, < 0.5% unintended complete-frame drops, ≤ 50 ms absolute A/V drift, and valid output after Stop. A 30-minute 4K/30 run is additional stress evidence. Sample RSS once per second after a two-minute warmup; the provisional stress gate is ≤ 128 MiB growth from minute 2 to minute 30, and the 10/30/60-minute results must not show duration-scaled retained-buffer growth.

**Current evidence state:** Queue bounds, drop classes, 20 Hz audio-meter cadence, and rational timeline behavior pass focused tests. The long-duration fixture matrix and memory/drift gate remain `NOT MEASURED`.

### B3 — Move capture completion work off the main actor (P1/P2)

**Evidence:** `AppState.handleCapturedImage` synchronously saves/copies/indexes on the main actor. `HistoryStore.add` can encode PNG again, read the whole file for hashing, and persist its index.

**Tasks:**

- [x] Produce one durable encoded artifact and reuse or safely copy it for output/history when formats match.
- [x] Perform encoding, hashing, metadata extraction, and index persistence off the main actor.
- [x] Publish only final UI state on the main actor.
- [x] Preserve atomic writes and cancellation/error behavior.

**Gate:** `selection-commit → thumbnail-visible` remains within the approved p95 ≤ 500 ms budget, with a reference-machine target ≤ 300 ms and no main-thread stall > 50 ms. Define and report editor visibility separately rather than folding it into the thumbnail metric.

**Current evidence state:** Capture encoding, artifact writes, History hashing, and index JSON persistence run outside the main actor. One serial index owner covers every index read/write, each mutation persists a candidate snapshot before publishing it, and matching full-size PNG output reuses one encoded byte buffer for disk, History, and clipboard. The focused History suite passes 24 tests, including atomic failure rollback, Trash compensation, recovery journals, cancellation cleanup, and no transient `@Published` item on a failed write. The complete 504-test unit run passed with zero failures.

### B4 — Optimize only measured failures (P2)

**Candidates:**

- GIF PNG spool encode/decode and palette/LZW loops.
- Serial multi-display snapshots and dock pixel comparison.
- Eager history reconciliation at startup.

**Tasks:**

- [ ] Add representative 1280×720/10 fps and 2560×1440/15 fps GIF fixtures before changing the codec path.
- [ ] Reject a GIF frame before writing beyond the configured scratch limit.
- [ ] Lazy-load/reconcile History only if the 500-item startup gate fails.
- [ ] Parallelize or downsample overlay refinement only if the overlay-ready gate fails.
- [ ] Treat the proposed 500-item startup targets as provisional until they are added to the performance contract and measured on named reference and oldest-supported Macs.

**Gate:** Scratch usage never exceeds its configured cap. Across matched 30/60-second 2560×1440/15 fps import/play/edit/export/close fixtures, peak RSS is ≤ min(2 GiB, 12.5% of physical memory), retained RSS 30 seconds after close is ≤ launch baseline + 250 MiB, and the 30→60-second slope is ≤ 5 MiB/min. Status item/hotkeys p95 ≤ 500 ms warm and ≤ 1 second cold with 500 history items is an internal provisional target until the contract and two-machine gate are approved.

### B5 — Canvas and autosave budgets (P1)

**Tasks:**

- [x] Replay the deterministic 60-second `canvas-100-v1` pan/zoom/select/drag/resize/inspector script.
- [x] Signpost last edit, save scheduling, serialization, atomic replacement, and main-thread intervals.
- [x] Inject process kill, disk full, and write denial at atomic-write boundaries.

**Gate:** Canvas p95 frame time is ≤ 16.7 ms at 60 Hz; p99 and every hitch > 33.4 ms are reported. Autosave is scheduled ≤ 2 seconds after the last edit, causes no main-thread stall > 50 ms, and every injected failure preserves the prior valid generation and immutable-original checksums.

**Current evidence state:** The Debug synthetic `canvas-100-v1` replay completed 3,600 logical frames with p95 1.616 ms, p99 1.909 ms, and zero hitches above 33.4 ms. The package-store matrix passes every save stage for simulated process termination, disk full, and write denial while preserving the prior manifest, generation, and original bytes. Autosave signposts cover the five required intervals. Reference-hardware signoff and a real external process-kill run remain `NOT MEASURED`.

### B6 — Export and recovery budgets (P1)

**Tasks:**

- [x] Measure first visible progress, cancellation at 10/50/90%, worker shutdown, throughput, output validity, and encoder/fallback evidence.
- [x] Inject corrupt generated data and interrupted MP4/GIF export in addition to recording delegate failures.
- [x] Preserve the prior destination, prior manifest, and immutable originals under every injected failure.

**Gate:** Progress appears ≤ 500 ms; cancellation is acknowledged ≤ 500 ms and completes ≤ 2 seconds. MP4 p95 elapsed/media-duration ratio is ≤ 1.0 on the reference Mac and ≤ 2.0 on the oldest-supported Mac; GIF is ≤ 2.0/≤ 4.0. No cancelled, corrupt, or interrupted export replaces an existing destination.

**Current evidence state:** The focused Media Export and performance suites pass 34 tests. First progress appeared in 2.095 ms. Cancellation at 10%, 50%, and 90% preserved the prior destination, removed partial files, and stopped the export worker in under 10 ms in this run. MP4 and GIF corrupt/interrupted partials never commit. The result reports verified H.264 output and states that hardware encoder use and fallback are not observable through `AVAssetExportSession`. Reference and oldest-supported hardware ratio gates remain `NOT MEASURED`.

---

## Workstream C — Editors and annotations

**Outcome:** Still, video, and GIF edits are reversible, accessible, and rendered from the same project truth used by export.

### C1 — Latest-wins Video Studio persistence (P1)

**Evidence:** `VideoStudioDocument.scheduleSaveAndRebuild` launches untracked tasks, swallows persistence/rebuild errors, and allows rapid edits to overlap.

**Tasks:**

- [x] Keep one cancellable/debounced generation task.
- [x] Serialize package writes.
- [x] Rebuild the player only from the newest accepted snapshot.
- [x] Surface persistence/rebuild failures without discarding the current edit state.
- [x] Flush the newest accepted snapshot before window teardown.

**Gate:** Fifty rapid mutations reopen to the final model, stale rebuilds never replace the newest player item, and only the final generation completes persistence/rebuild. Injected save/rebuild failures remain visible, preserve current edits, and a close flushes the newest snapshot before teardown.

**Current evidence state:** The focused Video Studio suite passes 29 tests. Fifty rapid mutations reopen to the final model and publish one new durable generation. Revision checks block stale rebuilds. Save and rebuild failures remain visible without dropping edits. Close writes the newest snapshot synchronously.

### C2 — One edit gesture, one undo step (P1)

**Evidence:** Still inspector/Beautify and GIF controls can create a command, autosave, playback reset, or rebuild for every binding update. The still `UndoStack` is unbounded.

**Tasks:**

- [x] Add begin/preview/commit transactions to continuous inspector, Beautify, GIF, and Video controls plus committed text edits.
- [x] Preserve the existing one-command behavior for still move/resize and video overlay drags; add regression tests rather than rewriting those paths.
- [x] Coalesce a gesture into one undo entry and one autosave/rebuild.
- [x] Cap still-editor history at the existing media-editor convention of 100 entries.
- [x] Preserve exact before/after snapshots and redo invalidation.

**Gate:** A 100-update slider gesture and a committed text edit each create one undo step and one save/rebuild; cancelled/no-op edits create zero; undo/redo restores exact values and new edits invalidate redo. Annotation-heavy batch commands stay within the 100-entry bound without duration-scaled history memory.

**Current evidence state:** The focused still, GIF, and Video suites pass 57 tests. One hundred preview updates create one exact undo entry. Video publishes one durable generation. Cancelled and no-op transactions create no undo entry. New edits clear redo. Still history keeps the newest 100 commands. Existing still resize and video overlay gesture tests remain green.

### C3 — Preview/export renderer parity (P1)

**Evidence:** GIF preview uses SwiftUI while export manually draws only `prefix(4)` annotations. Video preview supports wrapped SwiftUI text while export rasterizes one Core Text line.

**Tasks:**

- [x] Reuse the existing `AeroOverlay`, `Annotation`, and `AnnotationRenderer` contracts plus only the pure `AeroOverlay ↔ Annotation` mapping extracted from `EditorProjectBridge`; do not add another overlay DTO or put persistence on the render path.
- [x] Create the smallest off-main raster adapter needed for media preview/export to consume the same immutable overlay snapshot.
- [x] Preserve crop, transparency, time range, z-order, and schema compatibility.
- [x] Add golden frames for still straighten + crop + Beautify, video multiline wrapping at crop boundaries and timed-overlay activation edges, z-order overlap, opacity, and GIF output with more than four annotations.

**Gate:** Preview and exported frames agree within the numeric tolerance approved in B1 for the golden corpus; until approval, tests report deltas and require manual review rather than claiming pass. Every valid annotation is rendered in z-order.

**Current evidence state:** The focused GIF and media renderer suites pass 88 tests. GIF preview and export share `GIFCaptionRenderer` and render more than four active captions. Video preview and export share `MediaTextOverlayRasterizer`; existing export tests cover multiline text, timed half-open activation edges, opacity, and deterministic z-order. The still pipeline test covers straighten, crop, Beautify, output size, and repeatable bytes. B1 tolerance approval and manual golden review remain open, so this does not claim numeric visual approval.

### C4 — Accessible layers and scoped shortcuts (P1)

**Evidence:** Still-canvas annotations are not accessibility elements. GIF annotation rows are display-only. Video has incomplete duplicate/delete/reorder coverage. Root key handlers wrap text fields.

**Tasks:**

- [x] Add a compact layer/annotation list inside the existing inspector shell, not a new window.
- [x] Support select, rename/edit text where applicable, duplicate, delete, reorder, and reveal/focus.
- [x] Give video/GIF overlays the same minimum command set.
- [x] Disable editor shortcuts while native text editing owns input.
- [x] Expose Video Studio Undo/Redo through discoverable enabled-state controls or native Edit-menu actions, not only a root key handler.

**Gate:** Signed UI tests can select/edit/delete an annotation without canvas clicking and invoke Video Undo/Redo through a discoverable action. While every native text/numeric field owns focus, still tool letters, GIF Space/Left/Right, Video `J/K/L/I/O/Delete`, and Command-Z edit or navigate the field without changing document state. VoiceOver exposes kind, order, selection, and available actions.

**Current evidence state:** The focused still, GIF, and Video model suites pass 60 tests. The existing still inspector and the GIF and Video Studio lists expose selection, kind, order, edit/rename, duplicate, delete, reorder, and reveal actions. Video Undo and Redo are visible controls with enabled state. Shared shortcut scope leaves native text editors in control. Signed UI and manual VoiceOver verification remain open.

### C5 — Professional productivity after correctness (P2)

**Sequence:**

1. Multi-selection clipboard.
2. Align/distribute.
3. Common-bounds group resize with one undo step.
4. Reusable annotation style presets.
5. Incremental rich timed annotations in Video/GIF using the existing still engine.

Each item requires a separate acceptance slice. Rotation, grouping/locking, a full layer hierarchy, and new annotation kinds remain P3 until workflow evidence justifies them.

**Gate:** Each shipped action is available by pointer and keyboard/numeric control, persists through project reopen, and matches preview/export.

---

## Workstream D — Capture and UI/UX

**Outcome:** The fast path stays fast while every state is understandable, keyboard-operable, and visually testable.

### D1 — Reviewable area selection (P1)

**Evidence:** Area selection commits on mouse-up even though the view contains nudge and Enter-to-commit behavior.

**Tasks:**

- [x] Retain a dragged area for move, resize, aspect lock, and 1- or 10-point keyboard nudging.
- [x] Commit with Enter or double-click; cancel with Escape; click-drag on empty space starts over.
- [x] Preserve instant window click and the existing capture-immediately preference.
- [x] Verify exact coordinates at Retina and multi-display boundaries in model tests.

**Gate:** Area capture can be completed keyboard-only after the initial selection; model tests cover clamp, 1-/10-point nudge, aspect lock, restart, commit, cancel, and 1×/2× coordinate conversion.

**Current evidence state:** The focused selection and geometry suites pass 16 tests, including clamped 1-/10-point nudging, retained movement, anchored aspect snapping, restart behavior, and exact 1×/2× crop conversion. A signed live multi-display boundary run remains open.

### D2 — Clarify HUD and thumbnail state (P1)

**Evidence:** The idle HUD mixes still-capture modes with recording-only controls. Saved recording state hardcodes a destination. Screenshot thumbnail actions are hover-revealed and every screenshot is labeled as an area capture.

**Tasks:**

- [x] Group capture modes separately from recording options without adding controls.
- [x] Derive destination and capture-kind labels from actual state.
- [x] Keep Dismiss and one primary post-capture action permanently visible; leave secondary actions in the existing overflow/configuration path.
- [x] Expose selected modes and toggle values in the accessibility tree.

**Gate:** Tab/Space/Escape operate every HUD/thumbnail state; Dismiss and the primary action are discoverable without hover; labels distinguish area/window/screen; saved destination matches the real URL. During Share Safe scanning, Dismiss remains available while copy/share/edit remain blocked. Light/dark/Reduce Motion sweeps pass at 1× and 2×.

**Current evidence state:** The focused HUD model suite passes five tests. Capture and recording options are separate accessibility groups. Thumbnail labels now reflect area, window, screen, or scrolling capture. Saved-state labels derive the destination from the output URL. Dismiss and the primary action remain visible, including during Share Safe scanning. The signed keyboard and appearance sweep remains open.

### D3 — Truthful onboarding and useful Settings search (P1)

**Tasks:**

- [x] Let onboarding remain dismissible, but show **Ready** versus **Needs Attention** truthfully when permissions are absent.
- [x] On relaunch, preserve the user's choice while keeping recovery actions visible.
- [x] Deep-link Settings search results to the matching section/control and focus or reveal it.
- [x] Keep permission requests contextual rather than asking for every future capability up front.

**Gate:** Fresh-install granted/denied/dismissed/relaunch paths are covered; every search catalog entry reveals its exact section/control identifier within the viewport and focuses or visibly highlights it; no missing permission is hidden behind a completed-looking state.

**Current evidence state:** The focused Settings suite passes 14 tests. Onboarding shows **Needs Attention** when screen capture permission is absent and persists dismissal. Settings remains the recovery path. Every search entry maps to an exact rendered row and focus destination. A signed fresh-account/TCC path remains open.

### D4 — Make visual/accessibility QA executable (P1)

**Tasks:**

- [ ] Check in approved baselines for onboarding, Settings, HUD, thumbnail, still editor, Video Studio, and GIF Studio.
- [x] Compare screenshots rather than only attaching them.
- [x] Define deterministic fixtures, numeric pixel/color tolerances, and masks for approved dynamic regions.
- [x] Require explicit review for every baseline update; screenshot existence alone never passes.
- [ ] Run light, dark, Increased Contrast, and Reduce Motion variants.
- [ ] Complete the manual keyboard/VoiceOver permission matrix on a signed installed build.
- [x] Record blocked TCC/hardware rows as unverified rather than passing them.

**Gate:** The three golden workflows complete keyboard-only and with meaningful VoiceOver names, values, states, and actions; numeric visual diffs pass the approved tolerance/mask policy for every required appearance.

**Current evidence state:** The signed UI target includes a read-only numeric RGBA comparator with per-channel tolerance, differing-pixel ratio, top-left pixel masks, size checks, and an explicitly approved manifest. The complete signed run passed 15 tests with zero failures. Four visual rows skipped because approved baselines are unavailable. The one-click status-item regression, Share Safe review, privacy recovery, instant screenshot, still editor, GIF Studio, launch, and keyboard navigation rows passed. `docs/VISUAL_REGRESSION.md` records the review contract. Approved surface baselines and the manual keyboard/VoiceOver permission matrix remain open.

---

## Workstream E — Workflow, history, and release

**Outcome:** Daily use remains coherent beyond a single capture, and release claims are backed by real evidence.

**Tasks:**

- [x] Make History usable before background reconciliation finishes; preserve deterministic duplicate/missing-source repair.
- [x] Unify History, thumbnail, and editor actions around the same Copy, Save, Edit, Share Safe, Reveal, Recover vocabulary.
- [x] Keep content-free diagnostics opt-in and local unless a separately approved sender is introduced.
- [ ] Run the oldest-supported-hardware performance matrix.
- [ ] Run live 10/30/60-minute A/V sync, dropped-frame, energy, and interruption checks.
- [ ] Complete clean-account permission, signing, notarization, Gatekeeper, update, and offline smoke checks.
- [ ] Collect real beta crash-free/task-success evidence before changing external metrics to measured.

**Gate:** `docs/RELEASE_CHECKLIST.md` is complete for the exact exported artifact; consented beta sessions are ≥ 99.5% crash-free before release candidate; no manual/external result is inferred from unit tests; public copy matches the verified feature matrix.

**Current evidence state:** The app publishes the decoded History index before an off-main reconciliation scan. Snapshot comparison prevents a stale scan from overwriting new captures. The existing crash-safe repair path still removes deterministic duplicates and marks missing sources. Applicable History and thumbnail actions now use Copy, Save, Edit, Share Safe, Reveal, and Recover consistently. Diagnostics remain explicit-consent, bounded, content-free, local-only, and have no sender. Settings now reports both analytics and crash reports as Off. The complete local unit, signed UI, website, static, archive, and artifact preflight checks pass. Hardware, long-duration live media, approved visual baselines, clean-account distribution, and real beta evidence remain open.

---

## Execution phases

### Phase 0 — Truth, trust, and instrumentation

**Goal:** Close the P0 trust boundary and create measurements that make later optimization decisions objective.

**Tasks:**

- [x] Implement A1 Share Safe review boundary and decision-matrix tests.
- [x] Correct A3 website links, OS support, and claim matrix.
- [x] Add B1 signposts/counters without changing product behavior.
- [x] Approve or explicitly defer numeric preview/export and visual-regression tolerance/mask policies.
- [x] Refresh the current feature/risk inventory while preserving historical reports.

**Gate:** Trust tests pass, public links resolve, raw baseline traces exist for capture, startup, recording queue depth, GIF spool, and export, and tolerance policies are approved or recorded as unverified.

### Phase 1 — Recording and fast-path reliability

**Goal:** Make capture/recording bounded and truthful under success, failure, and backpressure.

**Tasks:**

- [x] Implement A2 terminal-error propagation.
- [x] Implement B2 recorder bounds and drop accounting.
- [x] Implement B3 off-main capture completion.
- [x] Execute B5 canvas/autosave and B6 export/recovery harnesses.
- [ ] Measure startup/overlay/GIF candidates before choosing any B4 optimization.

**Gate:** Delegate/process-kill/disk-full/write-denial/corrupt-cache/interrupted-export injection passes; the canonical 10/30/60-minute A/V matrix, capture-to-HUD and commit-to-thumbnail latency, canvas/autosave, export, main-thread stall, and scratch-limit gates pass on the reference machine. Hardware-specific release claims remain unverified until the oldest-supported run.

### Phase 2 — Editor correctness

**Goal:** Make persistence, undo, preview, and export agree before adding more tools.

**Tasks:**

- [x] Implement C1 latest-wins Video Studio persistence.
- [x] Implement C2 edit transactions and bounded undo.
- [x] Implement C3 shared overlay rendering.

**Gate:** Rapid-mutation, one-gesture/one-undo, save/reopen, and preview/export golden tests pass across still, Video, and GIF projects.

### Phase 3 — Interaction and accessibility

**Goal:** Make capture and annotation workflows operable without hidden pointer-only paths.

**Tasks:**

- [x] Implement C4 accessible layer lists and scoped shortcuts.
- [x] Implement D1 reviewable selection.
- [x] Implement D2 HUD/thumbnail truth.
- [x] Implement D3 onboarding/search behavior.
- [ ] Establish D4 visual/accessibility baselines.

**Gate:** Signed UI, keyboard-only, VoiceOver, permission-state, and appearance matrices pass the three golden workflows.

### Phase 4 — Professional depth

**Goal:** Add the smallest productivity features proven valuable after the correctness gates.

**Tasks:**

- [ ] Execute C5 as separately approved slices in its stated order.
- [ ] Optimize only the B4 candidates that missed measured budgets.
- [x] Improve History/action coherence without changing project ownership.

**Gate:** Every new action is reversible, persistent, accessible, and preview/export equivalent; the original instant-capture path does not regress.

### Phase 5 — Release evidence

**Goal:** Convert local green tests into a trustworthy distributable release.

**Tasks:**

- [ ] Complete Workstream E hardware, permission, beta, signing, and notarization evidence.
- [ ] Reconcile website/release notes against the final feature matrix.
- [ ] Review the exact exported artifact, not only the Xcode project.

**Gate:** The release checklist is human-approved with no open P0/P1 issue and no unverified result presented as passed.

## Dependency and parallelism

- Phase 0 gates precede performance optimization, public release, and new feature expansion. Isolated C1/C2 correctness fixes may proceed in parallel when they do not touch Phase 0 files or shared contracts.
- Phase 1 precedes media/editor feature expansion but does not block unrelated correctness tests and fixes.
- Phase 2 editor correctness and the non-overlapping parts of Phase 3 UI baselines may run in parallel.
- C3 owns shared overlay/render contracts while active; no other agent edits those files concurrently.
- C4/D2/D3 may run in parallel only when their file sets do not overlap.
- Phase 4 starts only after Phases 1-3 pass.
- Release evidence runs continuously, but Phase 5 owns the final decision.

## AGENTS.md execution section (add when implementation starts)

Use one controller and only the bounded subagent roles needed for the active phase. For cross-file work packages that touch shared contracts, generate a phase-gated prompt through the `ass-master-prompt` protocol.

- **Controller:** owns this roadmap, phase status, integration order, full gates, and final truth claims.
- **Trust/performance agent:** owns Share Safe decision tests, recording backpressure/error paths, signposts, and benchmarks.
- **Editor agent:** owns still-editor commands/undo/layers and may touch project bridges only when explicitly assigned.
- **Media agent:** owns Video/GIF document scheduling, overlay parity, playback, spool, and export.
- **UI/accessibility agent:** owns HUD, thumbnail, onboarding, Settings, visual baselines, and signed UI flows.
- Shared contracts—`AeroProject`, `AeroOverlay`, `Annotation`, `MediaCompositionModel`, `AeroTokens`, and renderer adapters—have one writer per phase.
- Every assignment names exact allowed files, forbidden overlap, required tests, manual/unverified gates, and the phase gate.
- No agent may claim manual TCC, VoiceOver speech quality, hardware, beta, notarization, or publication evidence it did not execute.
- No agent may add a duplicate model/design system, enable a mock action, weaken privacy defaults, or delete tests to pass.

## Acceptance criteria

- [x] A matched Share Safe scan never shares the original without per-attempt confirmation.
- [x] A terminal recording failure leaves no active-looking session or false completed artifact.
- [ ] Capture and recording meet approved latency, queue, drop, sync, memory, and stall budgets with raw evidence.
- [x] Continuous edits create one undo/save/rebuild transaction and editor histories remain bounded.
- [ ] Still, Video, and GIF preview/export render the same overlay snapshot within approved tolerances.
- [x] Area selection can be reviewed, nudged, committed, and cancelled coherently.
- [ ] Annotations and timed overlays can be selected and operated through an accessible layer path.
- [ ] HUD, thumbnail, onboarding, and Settings report actual state and remain keyboard-operable.
- [ ] Visual tests compare approved light/dark/contrast/motion baselines.
- [ ] Existing instant screenshot workflows gain no mandatory Studio, account, or cloud step.
- [x] Public website/release claims map to shipping code and evidence.
- [x] No new dependency, renderer, editor framework, or abstraction is added without a measured need.

## Validation commands

```text
git diff --check
xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests test CODE_SIGNING_ALLOWED=NO
xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests/PerformanceReleaseTests test CODE_SIGNING_ALLOWED=NO
xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
scripts/run-ui-tests.sh
pnpm --dir website build
```

## First action

Start Phase 0 by writing the Share Safe decision-matrix tests, then add the `reviewRequired` outcome and confirmation UI. This is the smallest change that closes the highest-impact trust gap; do not redesign Share Safe or Settings while making it.
