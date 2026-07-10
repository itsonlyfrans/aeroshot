# Settings + Editor elevation plan — 2026-07-11 design audit

## Goal

Make every settings and editor surface read as one custom-built instrument. Purely
visual/interaction work — zero feature or logic changes. Direction is the committed
"precision optical instrument" language: quiet native-material chrome, monochrome
iconography, one azure accent that only ever means interactive/selected, red reserved
for record.

## Evidence

- Live editor walkthrough (fresh debug build, `aeroshot://capture` → editor):
  `design/audit-shots/editor/editor-base.png`, `editor-crop.png`, `editor-inspector.png`.
  The crop shot proves the toolbar reflow; the third shot proves the instability —
  a scripted click on "inspector" landed on "zoom in" because crop mode had shifted
  every control index.
- Settings shots from 2026-07-10 (`design/audit-shots/settings-after-*.png`).
- Full code sweeps of `Settings/Panes`, `Settings/Design`, `Editor/*`, `GIFStudio/UI`,
  `MediaStudio/UI`, `DesignSystem/*` (findings inlined below with file:line).

## Overall assessment

Settings is 90% of the way there — tokenized, calm, correct in dark and light. Its
remaining debt is *discipline*: ~10 raw fill opacities where 4 tokens exist, four card
treatments, three section-header typographies, one real contrast bug, and native
controls leaking through the custom chrome. The editor is a generation behind: one
overloaded 25-control toolbar that reflows when crop is active, two competing
selected-state idioms, three shadow recipes, native pickers/sliders/color wells inside
custom panels, and zero Reduce Motion gating. The GIF/Video studios don't use the
design system at all — they read as a different app.

---

## Phase 0 — Design-system additions (prerequisite, no visual change by itself)

All later phases reference these. `AeroTokens` gains:

1. **Fill/border roles** (kills the 0.02–0.22 raw-opacity spread):
   - `Fill.rest = Color.primary.opacity(0.03)`
   - `Fill.hover = 0.06`
   - `Fill.pressed = 0.09`
   - `Fill.selected = 0.12`
   - `Border.subtle = 0.06`, `Border.hover = 0.12`
   - `Border.accentSelected = accent.opacity(0.6)` at `1.5`
   - `SettingsTheme.fillRest/fillHover/borderSubtle/borderHover` become re-exports.
2. **Typography helpers**: `Typography.body()` exists; add `typeBody`/`typeTitle`
   re-exports on `SettingsTheme`, and a single **section-header spec**:
   `.subheadline.weight(.semibold)` + `iconSizeSmall` symbol, secondary tint.
3. **Canvas/overlay constants** (new `AeroTokens.Canvas`): surface colors for the
   editor canvas (replacing hardcoded RGB), dim `black 0.5`, handle size `8`,
   handle stroke `1.5`, dash `[4,3]`, dot-grid `0.045 / 16pt / 1.2pt`.
4. **Radius policy**: only 7/10/14/18. All `±2` arithmetic radii and literals
   6/8/11/12 map to the nearest token (concrete sites listed in phases).
5. **Promote Settings controls to shared `Aero*` controls** (move + rename, Settings
   keeps type aliases so no pane churn): `AeroMenuPicker` (from SettingsMenuPicker),
   `AeroSegmentedControl`, `AeroSwitch` (SettingsToggle's switch), `AeroSliderRow`
   (SettingsValueSlider), `AeroFieldStyle` (from SettingsSearchField's chrome),
   `AeroChipButton`. Editor/studios consume these in Phases 1–2.

Gate: build + unit tests pass; Settings renders pixel-identical (re-exports only).

---

## Phase 1 — Critical

### Editor

1. **Stable toolbar architecture** (`EditorWindowController.swift:168-299`).
   Today: 25 controls, 4 dividers, one capsule; crop injects Menu + Apply + Cancel +
   Slider + degree label mid-strip (L171-185) and `.fixedSize` (L298) reflows the
   whole capsule. Restructure into **two fixed capsules + one contextual bar**:
   - Left capsule — *modes*: select/pan/crop | annotate group | redact group.
   - Right capsule — *document actions*: undo/redo | zoom cluster | beautify,
     inspector, ruler, templates | Save (primary) | export menu.
   - **Contextual crop bar**: a second, separate capsule that appears *below* the
     left capsule when `toolKind == .crop` (fade+slide, Reduce Motion → fade),
     containing aspect menu, straighten slider (as `AeroSliderRow`), degree readout,
     and Apply/Cancel as proper buttons (`AeroButtonStyle` primary/quiet). The main
     strips never change size. Matches how the selection HUD already handles modes.
   Why: the strip reflow is disorienting, the live A11y test proved control positions
   aren't stable, and 25 undifferentiated targets fail the 2-second read.
2. **One selected-state idiom** (`EditorWindowController.swift:220-229` vs `:308-310`).
   Tools use white-on-accent fill; Beautify/Inspector/Ruler use accent glyph tint.
   → All persistent toggles adopt the tool treatment (accent fill, white glyph).
   Why: two idioms for "active" makes state illegible at a glance.
3. **Inspector panel jump** (`AnnotationInspector.swift:188`).
   `height: selected == nil ? 210 : 540` snaps 330pt instantly. → fixed width 300
   stays; height becomes content-driven inside a max, animated with `Motion.spring`
   (Reduce Motion → none).
4. **Native controls inside custom chrome** — replace with Phase-0 shared controls:
   - `AnnotationInspector.swift:201-328`: raw `Picker` ×4 → `AeroMenuPicker`/
     `AeroSegmentedControl`; raw `Slider` → `AeroSliderRow`; raw `TextField` ×3 →
     `AeroFieldStyle`; raw `Toggle` ×2 → `AeroSwitch`. (Native `ColorPicker` wells
     stay — no custom equivalent exists; flagged in Phase 3.)
   - `BeautifyControls` (`EditorWindowController.swift:414-508`): raw switch Toggle,
     two raw Pickers, three raw Sliders → `AeroSwitch`, `AeroMenuPicker`,
     `AeroSliderRow`; drop the `Color.primary.opacity(0.02)` inner tint (L478).

### Settings

5. **Segmented-control contrast bug** (`SettingsSegmentedControl.swift:51-55`).
   Selected = `Color.white` text on `primary.opacity(0.12)` — illegible in light
   mode and the selected state carries no accent (the sharpest violation of the one-
   accent rule). → selected segment: `Fill.selected` + **accent underline or accent
   text** (pick in review; recommendation: accent-tinted fill `accent.opacity(0.15)`
   + `.primary` text + `Border.accentSelected` on the thumb), hover state on
   segments (`Fill.hover`), matching every sibling control.
6. **Native buttons/pickers/fields in chrome** — swap to shared controls:
   - `OutputSettingsPane.swift:65,77,105` `.roundedBorder` TextFields → `AeroFieldStyle`.
   - `RecordingSettingsPane.swift:72-78` native mic `Picker` → `AeroMenuPicker`
     (same concept as CapturePane's sound picker — currently two different controls).
   - `SettingsPermissionTile.swift:48-53`, `PrivacyFilterSettingsRow.swift:24,52`,
     `SettingsInlineCallout.swift:41`, `SettingsFooterActions` (`:75`),
     `ShortcutsSettingsPane.swift:86-91,126-130,233-243`, `SystemSettingsPane.swift:139-144`
     native `Button`s → `AeroChipButton` / `AeroButtonStyle(.quiet/.destructive)`.
   - `PrivacyFilterSettingsRow.swift:28` raw `ProgressView` → `AeroProgress`.

### Studios

7. **GIF/Video studio chrome adoption** (`GIFStudioView.swift`, `VideoStudioView.swift`).
   Both are native `Form`/`Section`/default controls with zero tokens — visually a
   different app. Minimum bar this phase: window surface + `AeroPanel` inspectors,
   section headers on the shared spec, `AeroButtonStyle` on all buttons,
   `AeroSegmentedControl` for VideoStudio's inspector tabs (L181-183), export
   progress → `AeroProgress` (GIF L211, Video L271), `AeroEmptyState` for
   "Preview unavailable" (GIF L65). Full control-by-control polish continues in P2.
   *Not touched:* effect-preview colors that represent exported output (click
   highlights etc.) — that's content, not chrome.

Gate: build + `AeroshotTests`; live render loop on editor (base/crop/inspector,
dark + light) shows no reflow of the main strips; light-mode segmented control
passes contrast; screenshots archived to `design/audit-shots/`.

---

## Phase 2 — Refinement

1. **Elevation unification** — one recipe per tier via `AeroPanel`/Elevation tokens:
   - Editor toolbar `.shadow(0.22/12/y5)` (`EditorWindowController.swift:297`),
     BeautifyControls `.shadow(0.24/16/y8)` + radius 14 (`:154-156`) →
     `AeroPanel(materialIntent: .floating)` (Elevation.floating 0.12/18/y8).
   - `SettingsPanel.swift:53-58` raw shadow → `Elevation.card`;
     `SettingsPaneLayout.swift:276` StatCard shadow → `Elevation.card`;
     `SystemSettingsPane.swift:194` app-icon shadow → `Elevation.card`.
2. **Border language: flat hairlines everywhere** —
   `SettingsPanel.swift:42-51` gradient border (0.14→0.04, width 0.8) and
   `SettingsSeparator` gradient (`:134-141`) → flat `Border.subtle` at 0.5, matching
   every card; `SettingsShellBackground.swift:21` pane border
   (`strokeHairline.opacity(0.6)`, width 1) → same recipe. One hairline app-wide.
3. **Accent + color discipline**:
   - Overview summary chips (non-interactive, accent-filled) → neutral
     (`Fill.selected` bg, `.secondary` text) — accent must stay interactive-only.
   - `SettingsPaneLayout.swift:194,203,305` per-pane tint washes on pager/jump
     badges (red wash on Recording cards) → monochrome badges; red stays only on
     the record glyph itself; `SettingsNavRail.swift:137` rest-state `pane.tint`
     icon → `.secondary` at rest.
   - `SettingsHotkeyRow.swift:68`, `PrivacyFilterSettingsRow.swift:50`,
     `SystemSettingsPane.swift:142`, `SettingsFooterActions` raw `.red` →
     `ColorRole.danger`.
   - **Sparkles escapes**: `CaptureSettingsPane.swift:210` Smart scan →
     `text.magnifyingglass`; `SystemSettingsPane.swift:76` setup guide →
     `book`. (`wand.and.stars` in ShortcutsPane L80 is the macOS convention —
     keep, noted.)
   - Editor canvas passive-crop **yellow** (`EditorCanvasView.swift:640`) →
     `controlAccentColor` (azure), consistent with active handles.
4. **Typography consolidation**:
   - One section-header spec across `SettingsPanel.swift:73-80`,
     `SettingsSectionLabel`, `SettingsSubsectionHeader` (currently three treatments).
   - Pinned bar (`SettingsPaneLayout.swift:113-116`) adopts hero title weight so the
     pin hand-off doesn't jump.
   - Editor hardcoded fonts: zoom readout 10pt bold mono
     (`EditorWindowController.swift:210`) → `typeSmall(.semibold)` mono; Save 11pt
     (`:252`), strip 11pt (`:292`), Beautify labels 9/10pt (`:423,435,452,485,491`)
     → `typeMicro`/`typeSmall`; studio `.headline` headers → `Typography.title`.
5. **Radius/spacing cleanup** (mechanical, from sweep):
   `SettingsKeycap` 6 → 7; filename preview 6 → 7 (`OutputSettingsPane.swift:155`);
   mock cards 8 → 7 (`RedactionStylePicker.swift:102`, `CaptureSettingsPane.swift:266`);
   hero badge 11 → 10 and 38×38 → `iconBadgeSize` 36 (`SettingsHeroHeader.swift:44-49`);
   all `controlRadius ± 2` arithmetic (7 sites) → nearest token; editor Save radius 7
   literal (`:256`) → `Radius.small`; non-token spacings 1/3/5/7/10/14 → scale.
6. **Card consolidation**: `RedactionStyleCard` re-implements `SettingsSelectionCard`
   byte-for-byte (`RedactionStylePicker.swift:61-72`) → reuse the component; StatCard
   vs JumpCard raised-card treatments unify (same border, same Elevation.card, same
   hover); `RecordingSettingsPane.swift:23` format cards `HStack` → `LazyVGrid` like
   every other selection-card grid.
7. **System pane hero** (`SystemSettingsPane.swift:188-221`): bespoke header →
   `SettingsHeroHeader` with the app icon as leading art, preserving version +
   status badge as the hero's chip row. One hero pattern app-wide.
8. **Editor canvas chrome tokens** (`EditorCanvasView.swift`): background RGB pairs
   (L40-44) → `Canvas.surface`; crop border white 1.5 (L627) → adaptive
   `Canvas.handleStroke`; crop corner dots unify with selection-handle rendering
   (white-stroked azure dots, L599-609 spec); text-editing NSTextView black-15%
   background (L453-456) → `Canvas` token w/ adaptive contrast; ruler 0.92 alpha +
   9pt mono (L677-687) → tokens.
9. **Editor Save button** (`EditorWindowController.swift:250-258`) → shared
   `AeroButtonStyle(.primary)` (white-on-accent, press, focus ring built in);
   toolbar menus (`:230-247, :260-290`) → `AeroMenuPicker` hover treatment with
   Reduce Motion gating (hand-rolled hover today, ungated).

Gate: build + tests; side-by-side before/after of all 8 settings panes + editor
(base/crop/beautify/inspector) + both studios, dark and light, reviewed.

---

## Phase 3 — Polish

1. **Pressed + focus states app-wide**: no Settings component uses
   `Control.pressScale/pressOpacity` and none has a focus ring despite
   `AeroTokens.Focus` and `aeroFocusRing` existing. Add pressed (0.96/0.70) and
   focus rings to: nav items, selection cards, jump/stat cards, chip buttons,
   toggles, segmented segments, disclosure/expandable headers, hotkey reset,
   editor tool buttons (have press, no focus ring), studio controls.
2. **Motion discipline**: raw durations → `Motion` tokens and Reduce Motion gating
   where missing — editor `.easeOut(0.14/0.16)` (`EditorWindowController.swift:223,305,322`),
   `EditorToolbarButtonStyle` ungated scaleEffect (`:405-412` — replace with
   `AeroButtonStyle`), GIF studio 0.16 (`GIFStudioView.swift:31`), Capture pane pulse
   0.4/0.5 (`CaptureSettingsPane.swift:295-303`) → nearest token or documented
   exception. Hover-fill inconsistency 0.04 vs 0.06 (SettingsToggle L63,
   DisclosureRow L66 vs ExpandablePanel/QuickLink) → `Fill.hover`.
3. **Hover-reveal secondary affordances**: hotkey reset buttons
   (`SettingsHotkeyRow.swift:35-39`) visible on every row at rest → reveal on
   row hover/focus (calmer rows, matches reduction filter).
4. **Empty/edge states**: `SettingsPathField` empty path renders an empty pill →
   placeholder "No folder selected" + subdued style; VideoStudio "Generating
   thumbnails…" raw placeholder (`VideoStudioView.swift:142-143`) → skeleton
   shimmer via `AeroProgress`/placeholder primitive (Reduce Motion → static).
5. **Editor pane segmented overload** (`EditorSettingsPane.swift:38-45`): two
   stacked 4+-segment controls risk truncation at 680pt → gradient preset becomes
   `AeroMenuPicker` (aspect stays segmented at 3).
6. **Accessibility completion**: `.isSelected` on Beautify/Inspector/Ruler toggles;
   `accessibilityLabel` on Beautify/Ruler buttons and both toolbar menus
   (`EditorWindowController.swift:220-229,230,260`); VoiceOver spot-pass on editor
   toolbar + inspector; verify studio frame-timeline traits.
7. **Disabled-state consistency**: `OutputSettingsPane.swift:120` manual
   `.opacity(0.45)` vs `.disabled` elsewhere → one disabled recipe (opacity token).
8. **Dot grid + micro-texture**: tokenize `EditorCanvasView.swift:508-512`
   (0.045/16/1.2) into `Canvas` constants; verify visibility at 1× and 2×.

Gate: full walkthrough (capture → edit → beautify → save → settings sweep → both
studios) in dark + light; Reduce Motion on/off; VoiceOver spot-check; screenshots
archived.

---

## Explicitly out of scope (flagged, needs product decision)

- **Beautify gradient presets** (`BeautifySettings.swift:20-30`): these paint the
  *exported image*, not the chrome — product feature, palette untouched here.
- **VideoStudio effect-preview colors** (yellow/orange click-highlight overlays):
  they preview exported effects — content, not chrome. Only the studio's own
  chrome (playhead, tabs, panels) is in scope.
- **Editor status readout** (canvas dimensions / cursor position — a "precision
  instrument" wants one): new UI surface = new functionality. Product call.
- **Native `ColorPicker` wells** in the inspector: keeping native until a custom
  color well is designed; a bespoke one is a component-design task of its own.

## Verification

- Per phase: `xcodebuild build` + `AeroshotTests`; window-capture render loop
  (build → `open` → `aeroshot://capture?mode=screen` → `screencapture -l`) for
  editor states and all panes, dark + light; archive under `design/audit-shots/`.
- Phase 1 gate additionally: scripted AX click-through of the editor toolbar
  (the button-index instability found in this audit becomes the regression test).
