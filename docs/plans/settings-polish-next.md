# Settings polish — next two features

Both follow the established direction: neutral charcoal glass, color only for
semantic state, section labels outside wells, every control with hover /
pressed / focus states and Reduce Motion support. Verify each with the
window-capture render loop (build → `open` → `screencapture -l <windowID>`)
in dark **and** light mode.

---

## 1. Redaction style preview cards (Capture → Share Safe)

**Goal.** Replace the Blur / Pixelate / Redact segmented control with three
Droppy-style preview cards, each rendering its effect on a tiny sample "screenshot"
so the user sees the tradeoff instead of reading it.

### UI spec

- Three cards in an `HStack`, equal width, inside the existing Share Safe well.
- Each card: a 96×56 pt mock screenshot (rounded 8 pt) with two "text lines"
  (capsules) and one highlighted "sensitive" line, effect applied to the
  sensitive line only:
  - **Blur**: sensitive capsule drawn with `.blur(radius: 3)`.
  - **Pixelate**: sensitive line drawn as a row of 4–5 small squares
    (mosaic look — no live filter needed).
  - **Redact**: sensitive line as a solid black rounded rect.
- Below the mock: title (`.subheadline.semibold`) + one-line caption
  (`.caption`, `.secondary`): "Reversible-looking, softest" / "Obscures while
  keeping shape" / "Solid black, cannot be recovered".
- Selection state matches `SettingsSelectionCard`: neutral fill
  `Color.primary.opacity(0.08)`, accent ring `SettingsTheme.accent.opacity(0.6)`
  at 1.5 pt. Hover: fill `0.06`, scale 1.01 (gated by Reduce Motion).

### Implementation

1. New file `Aeroshot/Settings/Design/RedactionStylePicker.swift`:
   - `RedactionStylePicker(selection: Binding<ShareSafeRedactionStyle>)`.
   - Private `RedactionPreviewMock(style:)` draws the sample; pure shapes,
     no images, so it adapts to both color schemes via `.primary` opacities.
2. In `CaptureSettingsPane` (Share Safe panel), replace the
   `SettingsSegmentedControl` bound to `shareSafeRedactionStyle` with
   `RedactionStylePicker`; keep the existing explanatory footer text.
3. Keep the "Redaction style" title + description block above the cards.

### States & a11y

- Each card is a `Button` with `.accessibilityLabel("<Style>, <caption>")`
  and `.isSelected` trait; haptic on select; spring animation on ring move.
- Keyboard: cards are focusable in order; no stray mouse-focus ring
  (`.focusable(interactions: .activate)` if needed).

### Verify

- Render Capture pane, crop to Share Safe at 2×: ring on the current style,
  blur actually blurred, mosaic legible at small size, dark + light.

---

## 2. Permissions overview disclosure row (System → Permissions)

**Goal.** Droppy's "Permissions Overview — 8 of 9 granted ⌄" pattern: a compact
summary row that collapses the two permission tiles by default, so a healthy
system shows one calm line instead of two big tiles.

### UI spec

- First row of the Permissions well:
  - Left: title "Permissions overview" (`.body.medium`) + caption
    "Review and grant everything Aeroshot can use."
  - Right: status pill — green `2 of 2 granted` / orange `1 of 2 granted`
    (reuse `SettingsStatusBadge`) + chevron that rotates 90° when expanded.
- Collapsed by default **only when all granted**; auto-expanded when anything
  is missing (never hide a problem behind a disclosure).
- Expanded content: the two existing `SettingsPermissionTile`s + the
  "Open setup guide" link, separated by `SettingsSeparator()`.
- Expansion animates with `SettingsTheme.spring` (Reduce Motion → no motion);
  content uses `.transition(.opacity.combined(with: .move(edge: .top)))`.

### Implementation

1. New file `Aeroshot/Settings/Design/SettingsDisclosureRow.swift`:
   - Generic `SettingsDisclosureRow(title:subtitle:badgeText:badgeTone:isExpanded:)`
     with `@ViewBuilder` content — reusable for future collapsed groups
     (e.g. Advanced in System).
   - Row is a full-width `Button` with hover fill (same treatment as
     `SettingsToggle`), chevron `rotationEffect` animated.
2. In `SystemSettingsPane`:
   - `@State private var permissionsExpanded = !SettingsPermissions.allGranted`
     (initialized in `onAppear` so it re-evaluates per visit).
   - Wrap the two tiles + setup-guide link in the disclosure row inside the
     existing `SettingsPanel("Permissions", …)`.
   - Keep `permissionRefreshTick` re-render behavior; when a permission flips
     to missing while collapsed, auto-expand.
3. Optional follow-up: reuse the row for the "Advanced" expandable panel to
   retire `SettingsExpandablePanel` (one disclosure idiom app-wide).

### States & a11y

- Row: hover, pressed, focus; `.accessibilityAddTraits(.isButton)`,
  `.accessibilityValue(expanded ? "Expanded" : "Collapsed")`.
- Status must be text + color (the pill already is), never color alone.

### Verify

- Render System pane in three conditions: all granted collapsed, all granted
  expanded, one missing (auto-expanded, orange pill). Dark + light.
