# WP-00 golden workflow — Annotated documentation image

**Contract status:** Phase 0 product specification. Current screenshot editing is a baseline; editable project persistence, deeper geometry, and the final inspector behavior remain planned until evidenced.

## Outcome

A documentation author captures or opens an image, adds precise editable callouts and privacy redaction, reopens the work without flattening it, and exports a trustworthy documentation asset.

## Entry

- Choose Edit from the post-capture thumbnail, open a supported local image, or reopen an editable Aeroshot project from local History/Finder.
- Entry opens Studio only because the user chose to edit.
- The immutable source is retained in the project; generated previews and exports do not replace it.

## Critical path

1. Enter Studio with the source fitted on the canvas and the canvas focused.
2. Add a release-critical annotation such as an arrow, text label, step marker, rectangle, or privacy redaction.
3. Select the annotation directly or through an accessible object list/next-object command.
4. Move and resize it directly; set the same visible properties numerically in the inspector. For an arrow, head length and width are independently inspectable and adjustable.
5. Use undo/redo to verify that geometry and appearance remain reversible.
6. Run ShareSafe review before an external export/share action. Findings are visible and navigable; the user can return to the canvas to correct them.
7. Save or autosave the editable local project.
8. Reopen it and verify that source, crop/canvas state, annotations, z-order, appearance, and redactions remain editable.
9. Export PNG as the primary documentation output; Copy, Drag, and an explicit local Save remain available.

## Success exit

- The PNG is written or copied with the expected dimensions, color-profile policy, annotations, and privacy treatment.
- Studio retains a local editable project distinct from the flattened export.
- The export action reports completion and destination; the project remains open or can be closed normally.

## Cancellation

- Escape cancels the active draw/transform operation before it becomes a command.
- Undo reverses a committed edit without changing the immutable source.
- Cancel in Export returns to the intact project and leaves no file that appears complete.
- Closing with unsaved changes follows a clear Save, Don't Save, Cancel decision unless durable autosave makes the exact recovery state explicit.

## Failure recovery

| Failure | Required response and recovery |
|---|---|
| Autosave interrupted | Preserve either the last valid project generation or a discoverable recoverable generation; never replace both with a corrupt manifest. |
| Source/project is corrupt or incompatible | Do not mutate it; identify the failing asset/component, offer safe read-only or recovery options when possible, and preserve diagnostic details without content leakage. |
| Export validation or encoding fails | Keep the project editable; show the failed stage and offer Retry or revised settings; remove/quarantine incomplete output. |
| Destination unavailable/disk full | Keep the project and last valid autosave; offer Choose Location and Retry; never report completion. |
| Font/style unavailable on reopen | Preserve stored values, show a non-destructive fallback, and make the substitution explicit before export. |
| ShareSafe cannot complete | Fail closed for actions configured to require review; explain whether the user can retry, correct, or explicitly export locally under policy. |

## Accessibility contract

- Canvas objects and inspector fields have meaningful VoiceOver roles, names, values, selection states, and actions.
- Keyboard users can create, select, move, resize, delete, reorder where supported, change numeric properties, undo/redo, run ShareSafe, save, and export.
- Direct manipulation always has a numeric or command-based equivalent; precision does not require drag-only interaction.
- Focus does not jump between canvas, toolbar, inspector, findings, and export sheet after edits or validation errors.
- Color is never the sole signifier for selection, redaction findings, invalid fields, or export status; Increased Contrast and Reduced Motion are supported.

## Privacy and local-first contract

- Source, editable project, OCR/redaction analysis, and exported files remain local unless the user explicitly invokes an external share destination.
- ShareSafe analysis does not silently upload pixels or recognized text.
- Original media is immutable; redaction is represented as editable project data and is flattened only into an export.
- External share/export clearly identifies what will leave the device. Diagnostics exclude pixels, OCR text, annotations, filenames, and paths by default.

## Measurable acceptance criteria

These are release criteria to measure; no result is asserted here.

1. A fixed fixture completes capture/open → arrow → text/step → redaction → Save → close → reopen → PNG export with **all project elements still editable after reopen** and **0 source mutations**.
2. Arrow head length and width can each be changed both directly and numerically; exported geometry matches the project render snapshot within the approved golden-frame tolerance in **100% of fixture cases**.
3. Add, move, resize, property change, redaction, and crop commands each support undo/redo; **redo invalidates after a divergent edit** across the deterministic command suite.
4. With 100 visible annotations, canvas interaction frame time is **p95 ≤ 16.7 ms at 60 Hz** under the Phase 0 measurement protocol.
5. Autosave begins no later than **2 seconds after the last edit**, uses an atomic write, and produces **no main-thread stall over 50 ms** under the protocol.
6. Every injected autosave interruption leaves either the previous valid generation or one discoverable recoverable generation; **0 fixtures end with only an unreadable project**.
7. Keyboard-only and VoiceOver runs complete annotate → inspect → ShareSafe finding navigation → save → export with **100% required controls reachable, named, and stateful**.
8. A network-blocked run can open, annotate, review, save, reopen, and export PNG with **0 required network requests**.
9. Preview and PNG export consume the same immutable project snapshot and meet the approved visual/color parity tolerance; the exact delta and color-profile result are recorded, not inferred.

## Open decisions

- Exact golden-frame and color-difference tolerance for preview/export parity.
- Which ShareSafe findings block external share by default versus warn, and how an explicit override is audited without retaining captured content.
- Whether the first sellable slice includes z-order controls beyond bring forward/send backward.
- Project file extension, History retention defaults, and behavior for moved external sources.
