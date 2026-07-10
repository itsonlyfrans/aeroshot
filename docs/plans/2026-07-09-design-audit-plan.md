# Design audit remediation plan

## Goal

Fix the UI/UX defects found in the 2026-07-09 design audit of all surfaces (HUD toolbar, selection overlay, editor, floating thumbnail, settings, iconography). Purely visual/interaction work — no feature or logic changes. Executed phase by phase; each phase is reviewed before the next begins.

## Context

- Settings already has a token system (`Aeroshot/Settings/Design/SettingsTheme.swift`) and a correctly built dropdown (`SettingsMenuPicker.swift`) — these are the reference implementations.
- The rest of the app (HUD, editor, thumbnail, selection) hand-rolls values and uses `.menuStyle(.borderlessButton)`, which renders a custom label **plus** AppKit's automatic pull-down chevron (the "three dot arrow" defect).
- `Assets.xcassets/AccentColor.colorset` defines no color, so `Color.accentColor` resolves to system blue everywhere while Settings brands itself violet — two accent identities in one app.

## Phase 0 — Shared theme foundation

1. **Create `AeroTheme`** (new file, `Aeroshot/Utilities/AeroTheme.swift`) with app-wide tokens:
   - `accent` — violet `srgb(0.58, 0.28, 0.95)`, backed by the AccentColor asset
   - `strokeHairline` — adaptive hairline color replacing all `Color.white.opacity(0.14–0.16)` strokes (must be visible in light *and* dark mode)
   - `controlRadiusS = 7`, `cardRadius = 14`, `controlHeight = 28`
   - `overlayLabelBackground` — the dark pill used by selection labels/instructions (`NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.85)`)
   - Press feedback constants: `pressScale = 0.96`, `pressOpacity = 0.7` (currently 0.97/0.72 in HUD vs 0.96/0.68 in editor)
2. **Define AccentColor asset** — `Assets.xcassets/AccentColor.colorset/Contents.json`: universal color `srgb(0.58, 0.28, 0.95)` plus a dark-appearance variant. Every existing `Color.accentColor` reference unifies to brand violet automatically.
3. `SettingsTheme` stays; where it duplicates a shared value, it re-exports from `AeroTheme`.

Gate: app builds; Settings renders identically; HUD/editor/thumbnail accents are violet.

## Phase 1 — Critical

1. **Kill the "three dot arrow" dropdowns.** Replace `.menuStyle(.borderlessButton)` at all four live sites with the `SettingsMenuPicker` pattern (`SettingsMenuPicker.swift:27-53`): `.menuStyle(.button)` + `.buttonStyle(.plain)` + `.menuIndicator(.hidden)` + `.fixedSize()`, keeping the existing ellipsis/glyph label and adding a hover treatment matching sibling buttons.
   - `Aeroshot/HUD/HUDToolbarView.swift:60` (Record menu)
   - `Aeroshot/Editor/EditorWindowController.swift:159` (templates menu)
   - `Aeroshot/Editor/EditorWindowController.swift:193` (export ellipsis menu)
   - `Aeroshot/Thumbnail/FloatingThumbnailView.swift:78` (overflow ellipsis)
   - Gate: no automatic menu-indicator chevron renders next to any custom menu label anywhere in the app.
2. **Delete dead duplicate editor toolbars.** `EditorWindowController.swift` `editorHeader` (L224-330) and `toolRail` (L332-369) are never referenced by `body` and have already drifted (Save 32pt/radius 9 vs live 28pt/radius 7). Code deletion only.
   - Gate: editor builds and renders identically; no unreferenced toolbar code remains.
3. **Differentiate instant-fire HUD modes.** Screen and Record Screen fire immediately on click (`CaptureIntent.isInstant`, `AllInOneController.swift:84-95`) but render identically to arm-a-selection modes (`HUDToolbarView.swift:68-88`). Remove the selection capsule for instant intents (they never stay selected) and give them a subtle action treatment (press-flash or action tint).
   - Gate: an instant button is visually distinguishable from a mode button at a glance.
4. **Fix Record Area vs Record Screen iconography.** `record.circle` vs `record.circle.fill` (`CaptureIntent.swift:27-28`, `Hotkeys/Hotkey.swift:168-169`) differ only by fill — fill reads as *active state*, not a different mode. Keep `record.circle` for area; use a display-based glyph for full-screen recording (`display` + red tint, or a badge variant if available at the macOS 14 target).
   - Gate: the two record modes are distinguishable by shape, not fill.
5. **Fix HUD panel shadow.** The card's `.shadow(radius: 12, y: 6)` (`HUDToolbarView.swift:40`) is clipped by the 68pt panel (`HUDToolbarPanel.swift:7`), and the AppKit window also draws its own shadow (`:35`). Panel height 68 → 96; `hasShadow = true` → `false`.
   - Gate: shadow renders fully with no hard clip edge; only one shadow source.

## Phase 2 — Refinement

1. **HUD Record button** (`HUDToolbarView.swift:54-66, 99`): neutral at idle (currently permanently red — the loudest element in the bar, contradicting the file's own design comment); red reserved for live recording; wrap the Menu label in `HUDCommandButtonStyle` so it gets the same press feedback as siblings.
2. **Hairline strokes** — replace hardcoded `Color.white.opacity(0.14/0.15/0.16)` with `AeroTheme.strokeHairline`, applied via `strokeBorder`:
   - `HUDToolbarView.swift:39`, `EditorWindowController.swift:200, 328, 455`, `FloatingThumbnailView.swift:91`
3. **Idle foregrounds** — `.primary.opacity(0.76)` (`HUDToolbarView.swift:99`), `.primary.opacity(0.84)` (`EditorWindowController.swift:213`) → semantic `.secondary` idle / `.primary` hover.
4. **Editor control-size drift** — tool buttons 27pt/radius 6, Save 28pt/radius 7, inspector `.cornerRadius(10)` (deprecated modifier, non-continuous) → one control height (`AeroTheme.controlHeight`) and `controlRadiusS`; inspector uses `RoundedRectangle(…, style: .continuous)`.
5. **Magnifier center-pixel marker** (`MagnifierView.swift:35-62`): add a 1-device-pixel crosshair/box at loupe center (white stroke + dark contrast edge) so the loupe shows which pixel is the hotspot.
6. **Toast/icon unification**:
   - "Copied to clipboard": `AppState.swift:138` `doc.on.clipboard` → `doc.on.doc` (matches every copy button and `EditorWindowController.swift:177`).
   - Copy-text standardizes on `text.viewfinder` everywhere (History text quick-action currently uses `doc.on.doc`, `HistoryWindow.swift:216`).
7. **Recording indicator** (`Recording/RecordingController.swift:257-263`): replace the bare red `Circle()` with `record.circle.fill`; align control language with the rest of the app.
8. **Status item permission state** (`App/AppDelegate.swift:332-336`): the `!allGranted` branch assigns the same `camera.viewfinder` as the normal branch (dead `if/else`); give the missing-permission state a distinct badge glyph consistent with `exclamationmark.shield.fill` used in `SettingsNavRail.swift:90`.
9. **Beautify bar** (`EditorWindowController.swift:550-559`): hardcoded `.purple` → `AeroTheme.accent`; remove the redundant hidden-label toggle + separate "Beautify" text (one labeled toggle).
10. **Accessibility**:
    - `.accessibilityAddTraits(.isSelected)` on the active HUD mode (`HUDToolbarView.swift:84`) and active editor tool (`EditorWindowController.swift:219`).
    - `accessibilityLabel` on editor icon-only buttons (undo/redo/zoom, L118-138) — `.help` tooltips are not VoiceOver labels.
11. **Scroll glyph**: `arrow.up.and.down.text.horizontal` (`CaptureIntent.swift:26`, `Hotkey.swift:165`) is visibly denser than sibling glyphs at 15pt → simpler symbol (e.g. `arrow.up.and.down`).

Gate: side-by-side before/after of HUD, editor, thumbnail in light and dark mode reviewed and approved.

## Phase 3 — Polish

1. **Selection overlay**: show the pre-drag hint universally, not just in scroll/aspect-lock modes (`SelectionOverlayView.swift:333-337`) — one quiet pill: "Drag to select · Esc to cancel". Merge the duplicated pill-drawing code in `drawLabel`/`drawInstruction` (L393-441) into one helper using `AeroTheme.overlayLabelBackground`.
2. **HUD micro-motion**: animate mode-selection change (`withAnimation` around `model.selected` updates); remove the capsule double-hide (width *and* opacity, `HUDToolbarView.swift:104-105`); derive digit-shortcut labels from `CaptureIntent.digitKey` instead of the duplicate table (`HUDToolbarView.swift:110-120`).
3. **Thumbnail**: overflow ellipsis 12pt bold → 11.5pt semibold to match sibling action icons (`FloatingThumbnailView.swift:75` vs `:119`).
4. **Icon policy** (decide once, apply everywhere):
   - `square.grid.2x2` currently means both All-in-One capture and History "All" tab — reassign one.
   - `symbolRenderingMode(.hierarchical)` is HUD-only — pick one app-wide rendering policy.
   - Fill-vs-outline rule for `.circle` glyphs: filled = actionable/emphasis, outline = status/decoration.
5. **Settings type drift**: fold ~20 hardcoded `size: 9–12` fonts into two type tokens on `SettingsTheme`.
6. **Localization headroom**: HUD fixed width 396pt with 52pt `lineLimit(1)` labels (`HUDToolbarPanel.swift:7`, `HUDToolbarView.swift:97-100`) — size the panel from content.

Gate: full app walkthrough (capture → annotate → save → settings) shows no visual regressions; light/dark both reviewed.

## Out of scope (flagged, needs product decision)

- **Adjust-before-commit selection phase.** `mouseUp` commits instantly (`SelectionOverlayView.swift:200-208`); the existing arrow-key nudge and Enter-commit are only reachable mid-drag, which is undiscoverable. Adding an adjust phase is a behavior change — the gap between current and CleanShot-tier selection UX. Decide separately.

## Verification

- Build + unit suite after each phase (`xcodebuild build`, `xcodebuild test`).
- Manual pass per phase gate, light and dark mode.
- Accessibility spot-check with VoiceOver on HUD and editor after Phase 2.
