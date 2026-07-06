# WP-00 product contract — First sellable vertical slice

**Status:** Phase 0 PRD and interaction specification; not implementation evidence  
**Authoritative plan:** `docs/plans/2026-07-10-aeroshot-product-evolution-combined.md`  
**Golden workflows:** `WP-00-instant-screenshot.md`, `WP-00-annotated-documentation-image.md`, `WP-00-recorded-demo.md`

## Product promise

Aeroshot is a fast, native, local-first macOS capture utility with an optional Studio. A user can get a screenshot out in one gesture, or deliberately continue into a reversible editing workflow for precise documentation images and corrected screen demos. No account, cloud upload, or general-purpose video-editor complexity is required.

## Problem and target users

Product builders, developers, technical writers, support teams, and independent creators need to turn screen content into trustworthy documentation and demos. Today, Aeroshot has substantial capture foundations, but the first sellable experience is incomplete where media must remain editable, a recording must survive correction/interruption, annotations need precision, and export must agree with preview.

The primary job is: **capture now, then choose the minimum correction needed to publish a clear, private, professional artifact.**

## First sellable vertical slice

The slice is complete only when all three golden workflows pass together:

1. **Instant screenshot:** area/window/display → Copy, Save, or Drag with no mandatory Studio or project-management step.
2. **Annotated documentation image:** source → precise editable callouts/redaction → save/reopen editable project → privacy-reviewed PNG export.
3. **Recorded demo:** preflight → reliable pause/recovery → trim or delete one mistake range → timed callout → MP4 or GIF export.

This combines the plan's Milestone A foundations with the narrow Milestone B correction loop. It does not authorize Phase 1+ implementation while the WP-00 gate is open.

## Product principles

- **Instant first, deep on demand:** preserve one-gesture output; Studio is an explicit choice.
- **Local-first and private:** no mandatory network, account, telemetry, or upload.
- **Reversible by default:** immutable originals, non-destructive edits, atomic autosave, recoverable sessions, and cancellable export.
- **One interaction language:** image, video, and GIF share selection, inspector, undo, timed/untimed annotations, export validation, and project ownership semantics.
- **Direct plus precise:** every draggable visible property has a keyboard/numeric equivalent; arrowhead length and width are the canonical requirement.
- **Measured quality:** latency, frame time, synchronization, memory, recovery, color/parity, accessibility, and export correctness are release criteria, not aspirations.

## Functional requirements

| ID | Requirement | Slice priority | Verification source |
|---|---|---|---|
| FR-01 | Preserve area/window/display instant capture and immediate Copy, Save, Drag, Edit actions without a new mandatory step. | Must | Instant workflow AC 1–3 |
| FR-02 | Represent an edited image or recording as a versioned local project with immutable original assets, non-destructive edits, atomic autosave, and recovery metadata. | Must | Documentation AC 1, 5–6; Recording AC 3–4 |
| FR-03 | Support the release-critical annotation subset: arrow, text, step, shapes, crop, and privacy redaction, with select/move/resize, undo/redo, and numeric inspector control. | Must | Documentation AC 1–3 |
| FR-04 | Expose independently adjustable arrowhead length and width in direct/numeric editing and render them consistently in preview/export. | Must | Documentation AC 2, 9 |
| FR-05 | Provide recording preflight for source, dimensions/rate, cursor, system audio, microphone, webcam, and countdown, with visible permission/device health. | Must | Recording AC 3, 10 |
| FR-06 | Support Pause/Resume, Stop, explicit Cancel, corrected timestamps, durable session manifests, interruption/low-space recovery, and accurate post-recording status. | Must | Recording AC 1–3 |
| FR-07 | Open completed recordings in focused Studio without destructive transcoding; provide playback/seek, trim, and deletion of one selected mistake range. | Must | Recording AC 4–5 |
| FR-08 | Add an annotation with a time range and preview it from the same project snapshot used for export. | Must | Recording AC 5–7 |
| FR-09 | Export validated local PNG and MP4; export GIF with displayed effective timing, loop behavior, dimensions, and quality/size preset. Progress is timely and cancellation is safe. | Must | Documentation AC 9; Recording AC 5–9 |
| FR-10 | Run ShareSafe review before policy-covered external export/share, with navigable findings and fail-closed behavior when review cannot complete. | Must | Documentation AC 6–7 |
| FR-11 | Reopen image, video, and GIF projects with edits still editable and originals unchanged. | Must | Documentation AC 1; Recording AC 4–7 |
| FR-12 | Keep local capture/edit/export fully usable offline and keep captured content/event data out of diagnostics by default. | Must | All workflow offline/privacy criteria |

## Interaction specification

### Capture and handoff

- Capture commands first produce the smallest surface needed to choose a source.
- Selection commit produces a non-modal thumbnail. Primary immediate actions are Copy/Save/Drag; Edit is present but never forced.
- Recording uses preflight because device, permission, and storage choices are consequential. Still capture does not inherit that step.
- Recording success is shown only after durable media/session finalization. The thumbnail then offers Edit, Copy/Drag, Save, and Reveal.

### Studio shell

- **Center:** media canvas/player and direct manipulation.
- **Leading/toolbar region:** mode and creation tools; it does not duplicate detailed property controls.
- **Trailing inspector:** selection-aware numeric and appearance controls; empty or multi-state values are explicit.
- **Bottom timeline:** appears only for time-based media. It initially supports seek, trim handles, one selected-range deletion, and time-ranged callouts; it is not a general NLE.
- **Export:** a sheet validates output, makes format/dimensions/timing visible, estimates size where specified, discloses fallback, and retains project context on error/cancel.

### Focus, commands, and feedback

- Command availability follows selection and project state. Disabled commands explain the missing precondition through accessible help.
- Canvas and inspector edits are one undoable command stream; export and ShareSafe do not clear undo history.
- Focus order is toolbar → canvas/player → timeline when present → inspector → document actions, while standard shortcuts may jump directly to regions.
- Status is never color-only. Completion, error, pause, recovery, selection, and privacy findings combine text/icon/shape with color.
- Reduced Motion removes decorative transitions. Increased Contrast and light/dark appearance preserve focus and state boundaries.

### Error and recovery grammar

Every consequential failure states: **what failed, what is safe, what may be missing, and the next valid actions**. Retry preserves configuration and edit state. Destructive discard is explicit. Partial exports are never presented as completed files. Relaunch surfaces recoverable sessions/projects before silently cleaning them.

## Privacy, security, and ownership requirements

- Processing is on-device by default. An external transfer requires a deliberate user action and identifies the leaving artifact.
- Original assets are immutable; project edits and generated caches are distinct. Caches are bounded, purgeable, and not ownership-critical.
- Event tracks are opt-in where sensitive, inspectable, and deletable. Keystroke capture is visibly active and excludes secure-input contexts.
- Permissions are requested at the moment their feature is chosen, explain purpose, and support retry after System Settings changes.
- Captured pixels, OCR text, event details, window titles, filenames, and paths are excluded from telemetry/crash diagnostics by default.
- The user's project and standard exports remain portable regardless of the later licensing/distribution decision.

## Accessibility requirements

- All three workflows must complete keyboard-only and with meaningful VoiceOver names, values, states, and actions.
- Direct manipulation has numeric/command equivalents; timeline range boundaries and canvas geometry are inspectable.
- Focus is visible, logically ordered, restored after sheets/errors, and never trapped in HUD, timeline, inspector, or export.
- Permission, privacy, validation, recording, recovery, and export states do not rely on color or motion.
- There is no timed interaction required to reach or operate a post-capture/post-recording action.

## Quality and acceptance boundary

The workflow documents contain the measurable task criteria. Performance targets remain provisional until baseline evidence records named hardware, fixture dimensions, display scale, color space, warm/cold state, sample count, percentile method, and background load. A target becomes a release gate only after the controller approves its baseline and protocol.

The vertical slice is accepted only when:

- every golden workflow passes its route, recovery, offline, keyboard, and VoiceOver criteria;
- preview and export consume the same immutable project snapshot and meet approved visual/color/timing tolerances;
- no acceptance fixture has a silent or ambiguous data-loss path;
- current screenshot speed is not regressed by a mandatory preflight, Studio, account, or project prompt;
- project ownership and local operation remain independent of distribution choice.

## Explicitly out of scope for the slice

- General-purpose multi-track editing, arbitrary clip reordering, full ripple semantics, speed/freeze segments, and advanced audio mixing.
- Rotate, grouping, locking, broad multi-select, advanced alignment/snapping, reusable style libraries, and complex layer management.
- GIF ping-pong, manual palette editing, sophisticated changed-region controls, and social preset breadth beyond validated essentials.
- Search/tags/favorites, AppleScript/CLI, team collaboration, mandatory cloud, hosted sharing, AI-generated content, livestreaming, Windows/mobile ports, and plugin marketplaces.
- Final license, price, or open-source/paid boundary before customer, support-cost, license-governance, signing, and update evidence exists.

## Current evidence boundary

Repository audit in the combined plan establishes existing still/scrolling capture, output-only MP4/GIF recording, capture-time audio/click/webcam options, shallow annotations, current image-editor undo/redo, and partial design tokens. It also records editable project persistence, media timeline editing, pause/resume, deeper arrow controls, and media-specific automated evidence as missing. This contract therefore uses **shall/must** for intended acceptance behavior and makes no claim that planned behavior currently exists.

## Unresolved product decisions

1. **Distribution:** fully open source, open core, or paid signed/source-available distribution. The separate controller-owned decision record must preserve this as a user decision backed by customer, license, support, signing, and update evidence.
2. **ShareSafe policy:** which findings block external transfer, what explicit local-export override exists, and how to record consent without retaining content.
3. **Project ownership details:** package extension, retention defaults, moved external-source behavior, and recovery retention/cleanup.
4. **Acceptance tolerances:** visual/color delta, timestamp tolerance beyond A/V drift, GIF size-estimation error, and hardware-specific GIF memory ceiling.
5. **Editing semantics:** exact first-slice selected-range deletion behavior and minimum z-order controls.
6. **Accessibility commands:** final keyboard geometry/timeline command map and VoiceOver announcement cadence.

Until these are resolved and the remaining WP-00 artifacts—including verified Luna identity—are approved, the Phase 0 gate remains open and Phase 1 is not authorized by this contract.
