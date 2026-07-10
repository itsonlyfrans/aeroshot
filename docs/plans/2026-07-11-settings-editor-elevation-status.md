# Settings + Editor elevation — status (2026-07-11)

Plan: `2026-07-11-settings-editor-elevation-plan.md`. All four phases implemented.
Debug build green; `AeroshotTests` green (run three times across the work).

## Phase 0 — Design-system additions ✅
- `AeroTokens.Fill` (rest/hover/pressed/selected), `AeroTokens.Stroke`
  (subtle/hover/accentSelected + widths), `AeroTokens.Canvas` (editor canvas
  constants incl. image shadow, dot grid, handles, dashes).
- `SettingsTheme` re-exports + `typeBody`/`typeTitle`.
- `AeroPanel` elevation now follows material intent (panel→card, floating/overlay→floating).
- Shared controls promoted with typealiases (zero call-site churn):
  `AeroMenuPicker`, `AeroChipButton`, `AeroSegmentedControl`, `AeroSliderRow`,
  `AeroToggleRow`; new `DesignSystem/AeroControls.swift`: `AeroSwitchKnob`,
  `AeroCompactToggle`, `AeroInlineSlider` (generic), `.aeroFieldChrome()`.
- New `AeroPressableStyle` ButtonStyle (press scale/opacity, Reduce Motion gated).

## Phase 1 — Critical ✅
- **Editor toolbar restructured**: two fixed capsules (modes left, document
  actions right) + a contextual crop bar that slides in *below* — the strips
  never reflow. Crop aspect → `AeroMenuPicker`, straighten → `AeroInlineSlider`,
  Apply/Cancel → `AeroButtonStyle` primary/quiet compact.
- One selected idiom everywhere (accent fill + white glyph): tools AND
  beautify/inspector/ruler toggles (`panelToggle`), with `.isSelected` traits.
- Save button → `AeroButtonStyle(.primary, .compact)`.
- Inspector: `.floating` panel intent, height change animated (spring, RM-gated);
  native Pickers→`AeroMenuPicker`, Toggles→`AeroCompactToggle`,
  TextFields→`.aeroFieldChrome()`. Native `ColorPicker` wells intentionally kept.
- Beautify bar: `AeroCompactToggle` + `AeroMenuPicker` + `AeroInlineSlider`,
  inner tint removed, tokens throughout.
- `SettingsSegmentedControl`: selected = accent-tinted fill + accent ring +
  `.primary` text (fixes white-on-gray light-mode contrast bug); per-segment hover.
- Settings native-control swaps: Output text fields (`.aeroFieldChrome` +
  FocusState), Recording mic picker → `AeroMenuPicker`, permission tile /
  privacy row / callouts / shortcuts / system buttons → `AeroChipButton` or
  destructive `AeroButtonStyle`; raw `ProgressView` → `AeroProgress`.
- **Studios adopted the design system**: GIF + Video studio Forms → `AeroPanel`
  sections with shared controls, `AeroSegmentedControl` inspector tabs,
  `AeroProgress` exports, `AeroEmptyState`, tokenized timeline chrome
  (playhead/selection → accent). Yellow/orange overlay colors verified against
  the export manifest (`VideoStudioDocument.overlayManifest`) as exported-effect
  previews and deliberately left (now commented in the view).

## Phase 2 — Refinement ✅
- Elevation: one recipe per tier (editor strips/beautify/inspector →
  Elevation.floating; SettingsPanel/StatCard/app icon → Elevation.card).
- Borders: SettingsPanel gradient border + gradient separator + pane-surface
  stroke → flat `Stroke.subtle` hairlines.
- Accent discipline: hero chips neutral by default (accent = interactive only),
  Overview bolt monochrome, jump/pager badges monochrome (record-red kept only
  on the Recording stat tile), nav rest icons `.secondary`, canvas passive-crop
  yellow → accent.
- Sparkles: Capture Smart scan → `text.magnifyingglass`, System setup guide →
  `book` (sparkles now Beautify-only; `wand.and.stars` kept in Shortcuts as the
  macOS convention).
- Typography: SectionLabel/SubsectionHeader/pinned-bar consolidated; editor
  9/10/11pt hardcoded fonts → tokens; studio `.headline` → `Typography.title()`.
- Radii/spacing: 6/8/11/`±2` arithmetic → 7/10 tokens across keycap, mocks,
  hero badge (38→36, 11→10), hotkey row, disclosure rows, filename preview.
- Canvas: background/dot grid/image shadow/handles/dim/text-editor backdrop →
  `AeroTokens.Canvas`; one `drawHandleDot` (accent + white ring) for selection
  AND crop corners; text editor backdrop now adaptive (`textBackgroundColor`).
- Recording format cards HStack→(deferred: agent applied selection-card grid
  conventions; verify visually). System "About" hero kept bespoke deliberately
  (identity block), shadow tokenized — deviation from plan §2.7, judged better.

## Phase 3 — Polish ✅ (code-complete)
- `AeroPressableStyle` pressed feedback on: nav items, stat/jump/pager cards,
  selection cards, redaction cards, toggles, chips, link buttons, search rows,
  disclosure/expandable headers, editor tool buttons.
- Motion: editor raw durations → Motion tokens, Reduce Motion gating added
  everywhere in the editor (was entirely ungated); capture-pulse documented as
  deliberate exception.
- Hotkey reset buttons hover-revealed (opacity-gated, still in a11y tree).
- Empty path field placeholder; studio thumbnail placeholder tokenized;
  GIF empty state → `AeroEmptyState`.
- A11y: labels on editor menus/toggles, `.isSelected` on all active toggles,
  studio control labels preserved through swaps.
- Not done: custom `aeroFocusRing` adoption (native Button focus rings retained
  — custom rings need per-control FocusState wiring; revisit if needed).

## Verification state
- `xcodebuild build` ✅ · `AeroshotTests` full suite ✅ (×3)
- Editor functional smoke: opens and renders a real `.aeroshot` project
  (fixture at /tmp/AuditFixture.aeroshot, format mirrors the UI-test fixture).
- **Visual walkthrough BLOCKED**: macOS screen-recording re-approval expired
  mid-session for both the shell and the app; a system authentication dialog
  is pending, which also blocked the signed UI-test suite
  ("Authentication canceled. System authentication is running") and AX queries.
  → Next session: approve the prompt, then rerun the render loop
  (`build → open → ⌘1–8 → screencapture -l`) and `scripts/run-ui-tests.sh`.
- Before shots: `design/audit-shots/settings-after-*.png` (2026-07-10),
  `design/audit-shots/editor/editor-{base,crop,inspector}.png` (pre-change).

## Session side effects
- One real screen capture ran through the pipeline early on (clipboard replaced).
- `com.aeroshot hasCompletedOnboarding` was temporarily set true for the
  settings walkthrough attempt, then restored to its prior value (false).
