# WP-00 visual direction — fast first, deep on demand

**Status:** Proposed visual contract for Phase 0 review  
**Artifact:** [`../references/WP-00-visual-reference-board.html`](../references/WP-00-visual-reference-board.html)  
**Truth boundary:** The board is a design reference, not implemented UI. It does not establish functional, accessibility, or performance evidence.

## Product expression

Aeroshot should feel like a precise native capture instrument that can unfold into a focused Studio. The default experience stays quiet and immediate; depth appears only after the user chooses Edit. Visual polish comes from consistent state, focus, hierarchy, window behavior, and feedback—not ornamental effects.

Three attributes govern the direction:

1. **Immediate:** capture modes are visually primary and the capture HUD remains a single compact command surface.
2. **Precise:** direct manipulation always has a numeric inspector equivalent; the selected object and its editable properties are unambiguous.
3. **Trustworthy:** recovery, local storage, privacy review, export destination, progress, and cancellation are visible before they matter.

## Evidence used

- `Aeroshot/Utilities/AeroTheme.swift`: catalog-backed azure accent, adaptive separator, 7 pt control radius, 14 pt card radius, 28 pt control height, restrained press feedback, dark overlay label.
- `Aeroshot/Settings/Design/SettingsTheme.swift`: 4/8/12/16/24 spacing scale, 18 pt panel radius, semantic success/warning states, subtle/hover borders and fills, reduced-motion-aware animation.
- `Aeroshot/HUD/HUDToolbarView.swift`: capture-first command grouping, regular material, continuous 15 pt container, selected underline, red recording semantics, monochrome symbol policy.
- Current audit screenshots in `design/audit-shots/`: quiet light/dark window shells, azure selection, lavender-neutral cards, strong grouping, monochrome navigation, green readiness, and red recording.
- Phase 0 and product principles in `docs/plans/2026-07-10-aeroshot-product-evolution-combined.md`.

This evidence constrains the reference; it does not imply that the proposed Studio, timeline, export, or unified project-history behavior exists.

## Surface contract

| Surface | Primary job | Hierarchy | Required states |
|---|---|---|---|
| Capture HUD | Choose a capture mode without turning capture into a setup flow | Mode → dimensions/selection → optional utility | Rest, hover, selected, keyboard focus, permission blocked, countdown, recording, cancel |
| Still Studio | Directly edit an image or annotation | Canvas → selected object → tool rail → inspector → export | Empty/no selection, single selection, mixed selection later, crop apply/cancel, dirty/saved, recovery |
| Media Studio | Trim a recording and place timed callouts | Preview → transport → timeline → inspector → export | Playing, paused, buffering, trim handles, time-range selection, missing media, recovered session |
| Timeline | Make time and edit boundaries legible | Playhead → selected clip/range → tracks → ruler | Keyboard-selected clip, focus ring, drag target, invalid drop, muted/locked, zoom, reduced motion |
| Inspector | Provide numeric truth for direct manipulation | Selection identity → common properties → advanced disclosure | Mixed values, invalid value, reset/default, disabled with reason, keyboard stepping, units |
| Export sheet | Make output consequences explicit | Recipe → estimate → settings → privacy result → destination → action | Ready, estimating, exporting, progress, cancellable, cancelled, recoverable failure, completed |
| History | Find, resume, recover, or export local work | Search/filter → recency → item state → contextual action | Empty, loading, selected, project/export badges, missing source, recovered, recently deleted |

## Semantic visual rules

### Color

- Azure is reserved for interaction, keyboard focus, selection, and the primary action.
- Red is reserved for active recording, destructive actions, and blocking failures. It is not a decorative accent.
- Green communicates completed safety/readiness checks; amber communicates attention without failure.
- Never use color as the only carrier of selection or status. Pair it with shape, border, label, symbol, or position.
- Light and dark are independently tuned appearances, not inverted values. Material and translucent fills must have opaque fallbacks for increased contrast and Reduce Transparency.

### Geometry and spacing

- Preserve continuous radii: 7 pt compact controls, 10 pt standard controls, 14 pt cards, and 18 pt major panels.
- Preserve the existing 4/8/12/16/24 spacing scale. Add a new spacing value only when a layout measurement proves the scale cannot express the requirement.
- Primary controls retain at least a 28 pt visual height and a 32 × 32 pt hit region where space permits. Compact timeline controls must remain keyboard reachable and expose accessible actions.
- Use hairlines for grouping, not decoration. Increased contrast replaces subtle/translucent hairlines with stronger opaque separators.

### Type and symbols

- Use the macOS system type family. Titles are semibold/bold; body and labels favor regular/medium; timestamps and numeric media values use tabular figures.
- Keep the existing monochrome SF Symbol policy. Filled symbols mean action/emphasis; outlines mean status/decoration.
- Never depend on an unlabeled novel symbol for a destructive, privacy, recovery, or export action.

### Elevation and material

- Elevation distinguishes transient command surfaces (capture HUD, sheets, popovers), not ordinary cards.
- Prefer native material for transient surfaces and opaque semantic surfaces for editing regions. Do not layer multiple translucent cards for visual novelty.
- Shadows remain neutral, broad, and quiet. Focus rings and borders—not shadow changes—communicate keyboard state.

### Motion

- Hover feedback completes in approximately 120 ms, matching current Settings policy.
- State transitions may use the existing restrained spring only where spatial continuity helps comprehension.
- With Reduce Motion, remove spring, scale, parallax, auto-scrolling, and animated playhead seeking; use an instant update or short crossfade.
- No animation may delay capture readiness, cancellation, pause, privacy action, or export progress.

## Interaction grammar

- Selection is shared across canvas, timeline, inspector, and history: azure outline or filled selection, visible focus treatment, and a text/semantic state.
- Direct manipulation and inspector values are two views of one model. Neither may silently override the other.
- Primary actions are verbs (`Capture`, `Export`, `Recover`). Destructive actions say what will be lost and support cancellation where feasible.
- Hover reveals convenience actions; it never contains the only route to an action.
- Every modal or sheet has one obvious default action, a visible Cancel action, Escape support, and focus restoration.
- Progress begins promptly, remains cancellable throughout export, and explains recoverable versus unrecoverable failure.

## Accessibility state contract

Every reference surface must be reviewed in light, dark, Increased Contrast, Reduce Transparency, and Reduce Motion appearances. Every golden workflow must complete keyboard-only and expose meaningful VoiceOver names, roles, values, states, shortcuts, and actions.

- Keyboard focus uses an external 3 pt semantic focus ring with adequate contrast and no clipping.
- The capture HUD supports predictable arrow-key movement between modes, Return/Space activation, digit shortcuts where already established, and Escape cancellation.
- Canvas and timeline objects expose selection plus move/nudge/resize/trim alternatives; precision is not pointer-only.
- Numeric inspector controls announce units, bounds, mixed values, and validation errors.
- Timeline time is available as text and accessibility values, not position alone.
- Error, recovery, and privacy messages move focus to their heading and provide a concrete next action.
- Minimum text and non-text contrast must be verified during implementation; the visual board itself is not contrast-test evidence.

## Privacy and trust presentation

- Local storage is the default and is stated where destination ambiguity exists.
- Upload, cloud, sharing, or user-owned endpoint actions are explicit and never implied by a generic `Save` label.
- ShareSafe findings are inspectable and fail closed. A green pass means a completed local review, not a guarantee that content is risk-free.
- Keystroke/event tracks are opt-in, visible when present, independently deletable, and excluded from diagnostics.
- Recovery state is visible in History and Studio without exposing captured content in logs or notifications.

## Non-copying constraints

Competitor evidence may inform category expectations only. Do not copy any competitor layout, icon arrangement, brand color, animation signature, wording, screenshot, illustration, asset, or distinctive sequence. Aeroshot’s direction must remain traceable to its existing native implementation and product principles.

Specifically:

- The compact HUD extends Aeroshot’s existing capture-first toolbar; it is not a replica of another capture utility.
- The Studio is a focused one-canvas/one-timeline workspace, not a general-purpose NLE or a clone of a competitor editor.
- The azure/red semantic split, spacing, radii, typography, and material behavior come from current AeroTheme/SettingsTheme evidence.

## What remains planned

- Unified semantic tokens and shared components are Phase 1 work.
- Project-backed Studio, timeline, selection-aware inspector, export recipes, ShareSafe export review, recovery states, and consolidated project history are future implementation.
- Exact colors, contrast ratios, window metrics, minimum sizes, animation durations, VoiceOver order, and keyboard maps require implementation prototypes and measured review.
- Light/dark reference approval and a verified Luna review remain Phase 0 gate inputs; this document does not approve either gate.

## Phase 0 visual acceptance checklist

- [x] A self-contained reference shows light and dark appearances.
- [x] Capture HUD, Studio, timeline, inspector, export sheet, and history are represented.
- [x] Keyboard focus, Increased Contrast, Reduce Motion, and VoiceOver contracts are represented.
- [x] The artifact explicitly says it is a design reference, not implemented UI.
- [x] Existing AeroTheme, SettingsTheme, HUD, and audit screenshots are named as evidence.
- [x] Non-copying constraints are explicit.
- [ ] Product owner approves the visual direction.
- [ ] Verified Luna review evaluates the direction and its competitor-workflow implications.
- [ ] Implementation prototypes verify contrast, target size, keyboard order, VoiceOver, Reduce Transparency, and reduced-motion behavior.

**Visual gate status: PARTIAL.** The reference deliverable exists, but approval, verified Luna review, and implementation validation remain open.
